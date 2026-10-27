package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// IdentityVerifier checks a driver's documents at source (kyc/surepass).
type IdentityVerifier interface {
	StartDigiLocker(ctx context.Context, redirectURL string) (domain.DigiLockerSession, error)
	DigiLockerStatus(ctx context.Context, clientID string) (domain.DigiLockerState, error)
	DigiLockerAadhaar(ctx context.Context, clientID string) (domain.AadhaarRecord, error)
	DrivingLicense(ctx context.Context, number string, dob time.Time) (domain.LicenseRecord, bool, error)
	BankAccount(ctx context.Context, number, ifsc string) (domain.BankAccountRecord, error)
}

// MaxChecksPerDay caps each kind of check per driver per rolling day. Every
// check is a paid call to the provider.
const MaxChecksPerDay = 5

var (
	// ErrVerificationUnavailable: the provider isn't configured or couldn't
	// answer. Worth retrying later.
	ErrVerificationUnavailable = errors.New("verification is unavailable right now, please try again in a few minutes")
	// ErrTooManyChecks: the driver used up today's attempts.
	ErrTooManyChecks = errors.New("too many attempts today, please try again tomorrow")
	// ErrVerificationPending: DigiLocker isn't finished yet.
	ErrVerificationPending = errors.New("finish the steps in DigiLocker first")
	// ErrNoDigiLockerSession: nothing to complete.
	ErrNoDigiLockerSession = errors.New("start DigiLocker verification first")
	// ErrVerificationFailed: DigiLocker failed or was abandoned.
	ErrVerificationFailed = errors.New("DigiLocker couldn't verify your Aadhaar, please try again")
	// ErrAadhaarMismatch: DigiLocker's Aadhaar isn't the number entered.
	ErrAadhaarMismatch = errors.New("the Aadhaar in your DigiLocker doesn't match the number you entered")
	// ErrLicenseNotFound: no licence with that number and date of birth.
	ErrLicenseNotFound = errors.New("we couldn't find this licence for your date of birth, check the number")
	// ErrLicenseRejected: the licence exists but can't be used to drive for us.
	ErrLicenseRejected = errors.New("this licence can't be used")
	// ErrBankAccountInvalid: the penny drop found no such account.
	ErrBankAccountInvalid = errors.New("we couldn't verify this account, check the account number and IFSC")
	// ErrIdentityLocked: name, date of birth and gender come from the Aadhaar.
	ErrIdentityLocked = errors.New("your name, date of birth and gender come from your Aadhaar and can't be changed")
)

// StartDigiLocker opens a DigiLocker session for the driver to verify their
// Aadhaar in. The Aadhaar number has to be saved first: what DigiLocker
// returns is checked against it.
func (s *DriverKYCService) StartDigiLocker(ctx context.Context, driverID string) (domain.DigiLockerSession, error) {
	if s.verifier == nil {
		return domain.DigiLockerSession{}, ErrVerificationUnavailable
	}
	profile, err := s.store.FindProfile(ctx, driverID)
	if err != nil {
		return domain.DigiLockerSession{}, err
	}
	if profile.AadhaarLast4 == "" {
		return domain.DigiLockerSession{}, fmt.Errorf("%w: enter your Aadhaar number first", ErrInvalidProfile)
	}
	if err := s.checkAllowance(ctx, driverID, domain.CheckDigiLocker); err != nil {
		return domain.DigiLockerSession{}, err
	}

	session, err := s.verifier.StartDigiLocker(ctx, s.digiLockerRedirect)
	if err != nil {
		s.recordCheck(ctx, driverID, domain.CheckDigiLocker, "", domain.CheckError, err.Error())
		slog.Error("kyc: starting digilocker", "driverID", driverID, "error", err)
		return domain.DigiLockerSession{}, ErrVerificationUnavailable
	}
	s.recordCheck(ctx, driverID, domain.CheckDigiLocker, session.ClientID, domain.CheckStarted, "")
	if err := s.store.SetDigiLockerSession(ctx, driverID, session.ClientID); err != nil {
		return domain.DigiLockerSession{}, err
	}
	session.RedirectURL = s.digiLockerRedirect
	return session, nil
}

// CompleteDigiLocker reads the result of the driver's DigiLocker session.
// On success the Aadhaar's name, date of birth and gender replace what the
// driver typed.
func (s *DriverKYCService) CompleteDigiLocker(ctx context.Context, driverID string) (domain.DriverKYC, error) {
	if s.verifier == nil {
		return domain.DriverKYC{}, ErrVerificationUnavailable
	}
	profile, err := s.store.FindProfile(ctx, driverID)
	if err != nil {
		return domain.DriverKYC{}, err
	}
	clientID := profile.DigiLockerClientID
	if clientID == "" {
		return domain.DriverKYC{}, ErrNoDigiLockerSession
	}

	state, err := s.verifier.DigiLockerStatus(ctx, clientID)
	if err != nil {
		slog.Error("kyc: digilocker status", "driverID", driverID, "error", err)
		return domain.DriverKYC{}, ErrVerificationUnavailable
	}
	switch state {
	case domain.DigiLockerPending:
		return domain.DriverKYC{}, ErrVerificationPending
	case domain.DigiLockerFailed:
		s.recordCheck(ctx, driverID, domain.CheckDigiLocker, clientID, domain.CheckFailed, "")
		s.endDigiLocker(ctx, driverID)
		return domain.DriverKYC{}, ErrVerificationFailed
	}

	rec, err := s.verifier.DigiLockerAadhaar(ctx, clientID)
	if err != nil {
		s.recordCheck(ctx, driverID, domain.CheckDigiLocker, clientID, domain.CheckError, err.Error())
		slog.Error("kyc: digilocker aadhaar", "driverID", driverID, "error", err)
		return domain.DriverKYC{}, ErrVerificationUnavailable
	}
	if rec.Last4 == "" {
		s.recordCheck(ctx, driverID, domain.CheckDigiLocker, clientID, domain.CheckFailed, "no Aadhaar number returned")
		s.endDigiLocker(ctx, driverID)
		return domain.DriverKYC{}, ErrVerificationFailed
	}
	if rec.Last4 != profile.AadhaarLast4 {
		s.recordCheck(ctx, driverID, domain.CheckDigiLocker, clientID, domain.CheckRejected,
			"Aadhaar ends "+rec.Last4+", entered "+profile.AadhaarLast4)
		s.endDigiLocker(ctx, driverID)
		return domain.DriverKYC{}, fmt.Errorf("%w (DigiLocker has one ending %s)", ErrAadhaarMismatch, rec.Last4)
	}
	if yearsBetween(rec.DateOfBirth, s.now()) < MinDriverAge {
		s.recordCheck(ctx, driverID, domain.CheckDigiLocker, clientID, domain.CheckRejected, "under age")
		s.endDigiLocker(ctx, driverID)
		return domain.DriverKYC{}, fmt.Errorf("%w: driver must be at least %d years old", ErrInvalidProfile, MinDriverAge)
	}

	if err := s.store.SaveAadhaarVerification(ctx, driverID, rec); err != nil {
		return domain.DriverKYC{}, err
	}
	s.recordCheck(ctx, driverID, domain.CheckDigiLocker, clientID, domain.CheckVerified, "")
	return s.Load(ctx, driverID)
}

// endDigiLocker forgets a session that has been read, so a retry starts a
// fresh one. Best-effort: a stale id only makes the next complete fail.
func (s *DriverKYCService) endDigiLocker(ctx context.Context, driverID string) {
	if err := s.store.SetDigiLockerSession(ctx, driverID, ""); err != nil {
		slog.Error("kyc: clearing digilocker session", "driverID", driverID, "error", err)
	}
}

// VerifyDrivingLicense looks the licence up with the driver's date of birth
// and saves it if it's valid for driving a car.
func (s *DriverKYCService) VerifyDrivingLicense(ctx context.Context, driverID, number string) (domain.DriverKYC, error) {
	number = strings.ToUpper(stripSpaces(number))
	if len(number) < 6 || len(number) > 20 {
		return domain.DriverKYC{}, fmt.Errorf("%w: enter a valid driving licence number", ErrInvalidProfile)
	}
	if s.verifier == nil {
		return domain.DriverKYC{}, ErrVerificationUnavailable
	}
	profile, err := s.store.FindProfile(ctx, driverID)
	if err != nil {
		return domain.DriverKYC{}, err
	}
	if profile.DateOfBirth == nil {
		return domain.DriverKYC{}, fmt.Errorf("%w: add your date of birth first", ErrInvalidProfile)
	}
	if err := s.checkAllowance(ctx, driverID, domain.CheckDrivingLicense); err != nil {
		return domain.DriverKYC{}, err
	}

	rec, found, err := s.verifier.DrivingLicense(ctx, number, *profile.DateOfBirth)
	if err != nil {
		s.recordCheck(ctx, driverID, domain.CheckDrivingLicense, "", domain.CheckError, err.Error())
		slog.Error("kyc: licence lookup", "driverID", driverID, "error", err)
		return domain.DriverKYC{}, ErrVerificationUnavailable
	}
	if !found {
		s.recordCheck(ctx, driverID, domain.CheckDrivingLicense, number, domain.CheckNotFound, "")
		return domain.DriverKYC{}, ErrLicenseNotFound
	}
	if reason := licenseProblem(rec, s.now()); reason != "" {
		s.recordCheck(ctx, driverID, domain.CheckDrivingLicense, number, domain.CheckRejected, reason)
		return domain.DriverKYC{}, fmt.Errorf("%w: %s", ErrLicenseRejected, reason)
	}

	// The number as the driver gave it identifies the licence; keep that
	// rather than the provider's formatting of it.
	rec.Number = number
	if err := s.store.SaveLicenseVerification(ctx, driverID, rec); err != nil {
		return domain.DriverKYC{}, err
	}
	s.recordCheck(ctx, driverID, domain.CheckDrivingLicense, number, domain.CheckVerified, "")
	return s.Load(ctx, driverID)
}

// carClasses are the licence classes that cover driving a car: light motor
// vehicles (LMV, LMV-NT, LMV-TR…), transport and heavier classes, whose
// holders also hold LMV.
var carClasses = []string{"LMV", "LIGHTMOTOR", "MOTORCAR", "TRANS", "HMV", "HGMV", "HPMV", "HTV", "MGV", "MPV"}

// licenseProblem says why a licence can't be used, or "" if it can. A
// licence with no expiry or classes on record passes here and goes to a
// person at submission (see reviewIssues).
func licenseProblem(rec domain.LicenseRecord, now time.Time) string {
	today := now.Truncate(24 * time.Hour)
	if !rec.ValidUntil.IsZero() && rec.ValidUntil.Before(today) {
		return "it expired on " + rec.ValidUntil.Format("2 Jan 2006")
	}
	if len(rec.Classes) > 0 && !coversCars(rec.Classes) {
		return "it doesn't cover cars (LMV)"
	}
	return ""
}

func coversCars(classes []string) bool {
	for _, c := range classes {
		norm := strings.Map(func(r rune) rune {
			if r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' {
				return r
			}
			return -1
		}, strings.ToUpper(c))
		for _, want := range carClasses {
			if strings.Contains(norm, want) {
				return true
			}
		}
	}
	return false
}

// verifyBankAccount runs the penny drop for SetBankAccount.
func (s *DriverKYCService) verifyBankAccount(ctx context.Context, driverID, number, ifsc string) (domain.BankAccountRecord, error) {
	if s.verifier == nil {
		return domain.BankAccountRecord{}, ErrVerificationUnavailable
	}
	if err := s.checkAllowance(ctx, driverID, domain.CheckBankAccount); err != nil {
		return domain.BankAccountRecord{}, err
	}
	ref := "xx" + number[len(number)-4:] + "/" + ifsc
	rec, err := s.verifier.BankAccount(ctx, number, ifsc)
	if err != nil {
		s.recordCheck(ctx, driverID, domain.CheckBankAccount, ref, domain.CheckError, err.Error())
		slog.Error("kyc: bank verification", "driverID", driverID, "error", err)
		return domain.BankAccountRecord{}, ErrVerificationUnavailable
	}
	if !rec.Exists {
		s.recordCheck(ctx, driverID, domain.CheckBankAccount, ref, domain.CheckNotFound, "")
		return domain.BankAccountRecord{}, ErrBankAccountInvalid
	}
	s.recordCheck(ctx, driverID, domain.CheckBankAccount, ref, domain.CheckVerified, "")
	return rec, nil
}

// checkAllowance refuses a check once the driver has used today's attempts.
func (s *DriverKYCService) checkAllowance(ctx context.Context, driverID string, kind domain.KYCCheckKind) error {
	n, err := s.store.CountChecks(ctx, driverID, kind, s.now().Add(-24*time.Hour))
	if err != nil {
		return err
	}
	if n >= MaxChecksPerDay {
		return ErrTooManyChecks
	}
	return nil
}

// recordCheck logs a provider call. Best-effort: losing an audit row must not
// fail the driver's step.
func (s *DriverKYCService) recordCheck(
	ctx context.Context, driverID string, kind domain.KYCCheckKind, ref string, outcome domain.KYCCheckOutcome, detail string,
) {
	if err := s.store.RecordCheck(ctx, driverID, kind, ref, outcome, detail); err != nil {
		slog.Error("kyc: recording check", "driverID", driverID, "kind", kind, "error", err)
	}
}

// reviewIssues lists what stops a complete KYC from clearing on its own;
// empty means every check agrees.
func reviewIssues(kyc domain.DriverKYC) []string {
	var issues []string
	p := kyc.Profile
	if p.LicenseName != "" && !namesMatch(p.FullName, p.LicenseName) {
		issues = append(issues, fmt.Sprintf("licence name %q differs from Aadhaar name %q", p.LicenseName, p.FullName))
	}
	if p.LicenseValidUntil == nil {
		issues = append(issues, "licence expiry date not on record")
	}
	if len(p.LicenseClasses) == 0 {
		issues = append(issues, "licence vehicle classes not on record")
	}
	if b := kyc.BankAccount; b != nil {
		switch {
		case b.VerifiedName == "":
			issues = append(issues, "bank didn't return the account holder's name")
		case !namesMatch(p.FullName, b.VerifiedName):
			issues = append(issues, fmt.Sprintf("bank account name %q differs from Aadhaar name %q", b.VerifiedName, p.FullName))
		}
	}
	return issues
}

// ListKYCReviews returns the drivers in status, for the back office.
func (s *DriverKYCService) ListKYCReviews(ctx context.Context, status domain.KYCStatus) ([]domain.KYCReview, error) {
	return s.store.ListKYCReviews(ctx, status)
}

// DecideKYC records a reviewer's decision. A rejection needs a note — it is
// what the driver is shown.
func (s *DriverKYCService) DecideKYC(ctx context.Context, driverID string, status domain.KYCStatus, note string) error {
	note = strings.TrimSpace(note)
	switch status {
	case domain.KYCVerified:
	case domain.KYCRejected:
		if note == "" {
			return fmt.Errorf("%w: a rejection needs a note for the driver", ErrInvalidProfile)
		}
	default:
		return fmt.Errorf("%w: status must be verified or rejected", ErrInvalidProfile)
	}
	return s.store.DecideKYC(ctx, driverID, status, note)
}
