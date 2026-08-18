package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/secret"
	"github.com/sarthi/server/internal/storage"
)

// SignedDocumentTTL is how long a pre-signed document URL stays valid. Short:
// the link is handed to one reviewer for one viewing, and anyone who obtains
// it in the meantime can read a driver's Aadhaar.
const SignedDocumentTTL = 5 * time.Minute

// MinDriverAge is the minimum age to drive for Sarthi, checked against the
// date of birth the driver enters.
const MinDriverAge = 18

// ErrInvalidProfile is returned when a submitted KYC field is malformed.
var ErrInvalidProfile = errors.New("invalid document details")

// ErrUnknownDocumentKind is returned for a document kind Sarthi doesn't collect.
var ErrUnknownDocumentKind = errors.New("unknown document kind")

// ErrKYCIncomplete is returned when a driver submits before every step is
// filled in. Its message names what is still missing.
var ErrKYCIncomplete = errors.New("document verification is incomplete")

// DriverKYCStore is the slice of persistence this service needs, declared
// consumer-side so it stays testable with a fake.
type DriverKYCStore interface {
	UpsertDocument(ctx context.Context, driverID string, p repository.UpsertDocumentParams) (domain.DriverDocument, string, error)
	ListDocuments(ctx context.Context, driverID string) ([]domain.DriverDocument, error)
	FindDocument(ctx context.Context, driverID string, kind domain.DocumentKind) (domain.DriverDocument, error)
	UpdateProfile(ctx context.Context, driverID string, p repository.UpdateProfileParams) error
	FindProfile(ctx context.Context, driverID string) (domain.DriverProfile, error)
	SetKYCStatus(ctx context.Context, driverID string, status domain.KYCStatus, recordSubmission bool) error
	UpsertBankAccount(ctx context.Context, driverID string, p repository.UpsertBankAccountParams) (domain.DriverBankAccount, error)
	FindBankAccount(ctx context.Context, driverID string) (domain.DriverBankAccount, error)
}

// DriverKYCService runs the driver app's six-step Document View: it validates
// what each step collects, stores images in the blob store and their metadata
// in PostgreSQL, and owns the driver's overall onboarding status.
type DriverKYCService struct {
	store  DriverKYCStore
	blob   storage.Blob
	cipher *secret.Cipher
	pepper []byte
	now    func() time.Time
}

// NewDriverKYCService wires the service to its store, blob backend, and the
// keys protecting Aadhaar and bank numbers at rest.
func NewDriverKYCService(store DriverKYCStore, blob storage.Blob, cipher *secret.Cipher, pepper []byte) *DriverKYCService {
	return &DriverKYCService{
		store:  store,
		blob:   blob,
		cipher: cipher,
		pepper: pepper,
		now:    time.Now,
	}
}

// Load returns everything the Document View needs to render its six steps.
func (s *DriverKYCService) Load(ctx context.Context, driverID string) (domain.DriverKYC, error) {
	profile, err := s.store.FindProfile(ctx, driverID)
	if err != nil {
		return domain.DriverKYC{}, err
	}
	docs, err := s.store.ListDocuments(ctx, driverID)
	if err != nil {
		return domain.DriverKYC{}, err
	}

	kyc := domain.DriverKYC{Profile: profile, Documents: docs}

	account, err := s.store.FindBankAccount(ctx, driverID)
	switch {
	case err == nil:
		kyc.BankAccount = &account
	case errors.Is(err, repository.ErrBankAccountNotFound):
		// Expected until the driver reaches the last step.
	default:
		return domain.DriverKYC{}, err
	}
	return kyc, nil
}

// UploadDocument stores one KYC image for a driver.
//
// raw is re-encoded before it is stored (see processDocumentImage), so what
// lands in the blob store is always a metadata-free JPEG we managed to decode.
// A retake replaces the previous image and the displaced object is deleted.
func (s *DriverKYCService) UploadDocument(
	ctx context.Context, driverID string, kind domain.DocumentKind, raw []byte,
) (domain.DriverDocument, error) {
	if !validDocumentKind(kind) {
		return domain.DriverDocument{}, ErrUnknownDocumentKind
	}

	clean, err := processDocumentImage(raw)
	if err != nil {
		return domain.DriverDocument{}, err
	}

	sum := sha256.Sum256(clean)
	key, err := documentObjectKey(driverID, kind)
	if err != nil {
		return domain.DriverDocument{}, err
	}

	// Bytes first, row second. The reverse order could leave a row pointing at
	// an object that was never written; this way a failure between the two
	// leaves an unreferenced object, which is harmless and sweepable.
	if err := s.blob.Put(ctx, key, clean, DocumentContentType); err != nil {
		return domain.DriverDocument{}, err
	}

	doc, displaced, err := s.store.UpsertDocument(ctx, driverID, repository.UpsertDocumentParams{
		Kind:        kind,
		ObjectKey:   key,
		ContentType: DocumentContentType,
		ByteSize:    int64(len(clean)),
		SHA256:      hex.EncodeToString(sum[:]),
	})
	if err != nil {
		// Roll the object back so a failed upload doesn't leave bytes behind.
		if delErr := s.blob.Delete(ctx, key); delErr != nil {
			slog.Error("kyc: could not remove orphaned object", "key", key, "error", delErr)
		}
		return domain.DriverDocument{}, err
	}

	// A retake's old image is no longer reachable; drop it rather than pay to
	// store a document nobody can reach. Best-effort: the row is already
	// correct, so a failure here is a storage leak, not a broken upload.
	if displaced != "" {
		if err := s.blob.Delete(ctx, displaced); err != nil {
			slog.Error("kyc: could not delete replaced document",
				"driverID", driverID, "key", displaced, "error", err)
		}
	}

	// Any new upload puts the driver back in front of a reviewer.
	if err := s.store.SetKYCStatus(ctx, driverID, domain.KYCIncomplete, false); err != nil {
		return domain.DriverDocument{}, err
	}
	return doc, nil
}

// OpenDocument returns a driver's stored image.
//
// It prefers a pre-signed URL so the bytes travel from object storage to the
// caller directly; url is empty when the backend can't sign (local disk in
// development), in which case body carries the image and the caller closes it.
func (s *DriverKYCService) OpenDocument(
	ctx context.Context, driverID string, kind domain.DocumentKind,
) (url string, body io.ReadCloser, err error) {
	if !validDocumentKind(kind) {
		return "", nil, ErrUnknownDocumentKind
	}
	doc, err := s.store.FindDocument(ctx, driverID, kind)
	if err != nil {
		return "", nil, err
	}

	url, err = s.blob.SignedGetURL(ctx, doc.ObjectKey, SignedDocumentTTL)
	if err == nil {
		return url, nil, nil
	}
	if !errors.Is(err, storage.ErrNoSignedURL) {
		return "", nil, err
	}

	body, err = s.blob.Get(ctx, doc.ObjectKey)
	if err != nil {
		return "", nil, err
	}
	return "", body, nil
}

// ProfileUpdate carries whichever typed fields a Document View step collected.
// Every field is optional: the app submits one step at a time, and a nil field
// leaves the stored value alone.
type ProfileUpdate struct {
	Transmission         *string
	FullName             *string
	DateOfBirth          *time.Time
	Gender               *string
	AadhaarNumber        *string
	DrivingLicenseNumber *string
}

// UpdateProfile validates and applies one step's fields.
//
// The Aadhaar number is the exception to "store what you're given": only its
// last four digits and a keyed fingerprint are persisted, never the number.
func (s *DriverKYCService) UpdateProfile(ctx context.Context, driverID string, u ProfileUpdate) error {
	var p repository.UpdateProfileParams

	if u.Transmission != nil {
		t := domain.DriverTransmission(strings.TrimSpace(*u.Transmission))
		if !validTransmissionValue(t) {
			return fmt.Errorf("%w: unknown transmission %q", ErrInvalidProfile, *u.Transmission)
		}
		p.Transmission = new(string(t))
	}

	if u.FullName != nil {
		name := strings.TrimSpace(*u.FullName)
		if len(name) < 2 {
			return fmt.Errorf("%w: full name is required", ErrInvalidProfile)
		}
		p.FullName = &name
	}

	if u.DateOfBirth != nil {
		dob := *u.DateOfBirth
		if age := yearsBetween(dob, s.now()); age < MinDriverAge {
			return fmt.Errorf("%w: driver must be at least %d years old", ErrInvalidProfile, MinDriverAge)
		}
		p.DateOfBirth = &dob
	}

	if u.Gender != nil {
		g := domain.Gender(strings.TrimSpace(strings.ToLower(*u.Gender)))
		if !validGender(g) {
			return fmt.Errorf("%w: unknown gender %q", ErrInvalidProfile, *u.Gender)
		}
		p.Gender = new(string(g))
	}

	if u.AadhaarNumber != nil {
		digits := stripSpaces(*u.AadhaarNumber)
		if !aadhaarPattern.MatchString(digits) {
			return fmt.Errorf("%w: enter a valid 12-digit Aadhaar number", ErrInvalidProfile)
		}
		p.AadhaarLast4 = new(digits[len(digits)-4:])
		p.AadhaarFingerprint = new(secret.Fingerprint(s.pepper, digits))
	}

	if u.DrivingLicenseNumber != nil {
		number := strings.ToUpper(stripSpaces(*u.DrivingLicenseNumber))
		if len(number) < 6 || len(number) > 20 {
			return fmt.Errorf("%w: enter a valid driving licence number", ErrInvalidProfile)
		}
		p.DrivingLicenseNumber = &number
	}

	if err := s.store.UpdateProfile(ctx, driverID, p); err != nil {
		return err
	}
	// Editing a step invalidates any earlier submission.
	return s.store.SetKYCStatus(ctx, driverID, domain.KYCIncomplete, false)
}

// SetBankAccount validates and stores where a driver's earnings are paid. The
// account number is encrypted before it reaches the database; only the last
// four digits are kept in the clear, for the driver to recognise.
func (s *DriverKYCService) SetBankAccount(
	ctx context.Context, driverID, holderName, accountNumber, ifsc string,
) (domain.DriverBankAccount, error) {
	holderName = strings.TrimSpace(holderName)
	if len(holderName) < 2 {
		return domain.DriverBankAccount{}, fmt.Errorf("%w: account holder's name is required", ErrInvalidProfile)
	}

	number := stripSpaces(accountNumber)
	if !bankAccountPattern.MatchString(number) {
		return domain.DriverBankAccount{}, fmt.Errorf("%w: enter a valid account number", ErrInvalidProfile)
	}

	code := strings.ToUpper(stripSpaces(ifsc))
	if !ifscPattern.MatchString(code) {
		return domain.DriverBankAccount{}, fmt.Errorf("%w: enter a valid IFSC code", ErrInvalidProfile)
	}

	sealed, err := s.cipher.Seal([]byte(number))
	if err != nil {
		return domain.DriverBankAccount{}, err
	}

	account, err := s.store.UpsertBankAccount(ctx, driverID, repository.UpsertBankAccountParams{
		AccountHolderName:      holderName,
		AccountNumberEncrypted: sealed,
		AccountNumberLast4:     number[len(number)-4:],
		IFSCCode:               code,
	})
	if err != nil {
		return domain.DriverBankAccount{}, err
	}
	if err := s.store.SetKYCStatus(ctx, driverID, domain.KYCIncomplete, false); err != nil {
		return domain.DriverBankAccount{}, err
	}
	return account, nil
}

// Submit closes the Document View: it re-checks that every step is filled in
// server-side — the app's own progress tracking is a convenience, not the
// authority — and moves the driver into the review queue.
func (s *DriverKYCService) Submit(ctx context.Context, driverID string) (domain.DriverKYC, error) {
	kyc, err := s.Load(ctx, driverID)
	if err != nil {
		return domain.DriverKYC{}, err
	}
	if missing := missingSteps(kyc); len(missing) > 0 {
		return domain.DriverKYC{}, fmt.Errorf("%w: %s", ErrKYCIncomplete, strings.Join(missing, ", "))
	}

	if err := s.store.SetKYCStatus(ctx, driverID, domain.KYCSubmitted, true); err != nil {
		return domain.DriverKYC{}, err
	}
	return s.Load(ctx, driverID)
}

// missingSteps names every Document View step still outstanding, so the app
// can tell the driver what to go back to rather than just refusing.
func missingSteps(kyc domain.DriverKYC) []string {
	var missing []string

	if kyc.Profile.Transmission == "" {
		missing = append(missing, "type of vehicle")
	}
	if kyc.Profile.FullName == "" || kyc.Profile.DateOfBirth == nil || kyc.Profile.Gender == "" {
		missing = append(missing, "photo and name")
	}
	if kyc.Profile.AadhaarLast4 == "" {
		missing = append(missing, "Aadhaar number")
	}
	if kyc.Profile.DrivingLicenseNumber == "" {
		missing = append(missing, "driving licence number")
	}
	if kyc.BankAccount == nil {
		missing = append(missing, "bank details")
	}

	uploaded := make(map[domain.DocumentKind]bool, len(kyc.Documents))
	for _, d := range kyc.Documents {
		uploaded[d.Kind] = true
	}
	for _, kind := range domain.DocumentKinds {
		if !uploaded[kind] {
			missing = append(missing, documentLabels[kind])
		}
	}
	return missing
}

// documentLabels names each image the way the driver app's steps do, for the
// "what's still missing" message.
var documentLabels = map[domain.DocumentKind]string{
	domain.DocumentSelfie:         "photo",
	domain.DocumentAadhaar:        "Aadhaar photo",
	domain.DocumentDrivingLicense: "driving licence photo",
}

// Validation patterns, matching the driver app's DocumentValidators so a
// value the app accepted isn't then refused here.
var (
	aadhaarPattern     = regexp.MustCompile(`^\d{12}$`)
	bankAccountPattern = regexp.MustCompile(`^\d{9,18}$`)
	ifscPattern        = regexp.MustCompile(`^[A-Z]{4}0[A-Z0-9]{6}$`)
)

// documentObjectKey builds a fresh key for an upload. The random suffix means
// a retake writes a new object instead of overwriting the old one in place, so
// a failed upload can never corrupt the image already on file.
func documentObjectKey(driverID string, kind domain.DocumentKind) (string, error) {
	suffix := make([]byte, 8)
	if _, err := rand.Read(suffix); err != nil {
		return "", fmt.Errorf("generating object key: %w", err)
	}
	return fmt.Sprintf("drivers/%s/%s/%s.jpg", driverID, kind, hex.EncodeToString(suffix)), nil
}

func validDocumentKind(k domain.DocumentKind) bool {
	return slices.Contains(domain.DocumentKinds, k)
}

func validTransmissionValue(t domain.DriverTransmission) bool {
	switch t {
	case domain.DriverTransmissionManual, domain.DriverTransmissionAutomatic, domain.DriverTransmissionBoth:
		return true
	}
	return false
}

func validGender(g domain.Gender) bool {
	switch g {
	case domain.GenderMale, domain.GenderFemale, domain.GenderOther:
		return true
	}
	return false
}

// yearsBetween returns completed years from dob to now.
func yearsBetween(dob, now time.Time) int {
	years := now.Year() - dob.Year()
	// Not yet past this year's birthday: one fewer completed year.
	if now.YearDay() < dob.YearDay() {
		years--
	}
	return years
}

// stripSpaces removes whitespace, so "1234 5678 9012" and "123456789012" are
// the same number — the app formats these fields for readability.
func stripSpaces(s string) string {
	return strings.Map(func(r rune) rune {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' || r == '-' {
			return -1
		}
		return r
	}, s)
}
