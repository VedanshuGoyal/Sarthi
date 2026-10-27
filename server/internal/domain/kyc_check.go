package domain

import (
	"time"
)

// Date is a calendar day with no time zone, sent as "YYYY-MM-DD".
type Date struct{ time.Time }

// MarshalJSON writes the day alone, so no client can shift it by a zone.
func (d Date) MarshalJSON() ([]byte, error) {
	return []byte(`"` + d.Format(time.DateOnly) + `"`), nil
}

// KYCCheckKind names what an identity check verified.
type KYCCheckKind string

const (
	CheckDigiLocker     KYCCheckKind = "digilocker"
	CheckDrivingLicense KYCCheckKind = "driving_license"
	CheckBankAccount    KYCCheckKind = "bank_account"
)

// KYCCheckOutcome is how one call to the verification provider went.
type KYCCheckOutcome string

const (
	CheckStarted  KYCCheckOutcome = "started"   // a DigiLocker session was opened
	CheckVerified KYCCheckOutcome = "verified"  // the record exists and passed our rules
	CheckPending  KYCCheckOutcome = "pending"   // DigiLocker not finished yet
	CheckNotFound KYCCheckOutcome = "not_found" // no such licence / account
	CheckRejected KYCCheckOutcome = "rejected"  // found, but fails our rules
	CheckFailed   KYCCheckOutcome = "failed"    // DigiLocker failed or was abandoned
	CheckError    KYCCheckOutcome = "error"     // the provider couldn't answer
)

// DigiLockerSession is a DigiLocker sign-in the driver has been sent to.
type DigiLockerSession struct {
	ClientID  string    `json:"-"`
	URL       string    `json:"url"`
	ExpiresAt time.Time `json:"expiresAt"`
	// RedirectURL is where DigiLocker sends the driver when they're done.
	RedirectURL string `json:"redirectUrl"`
}

// DigiLockerState is where a DigiLocker session stands.
type DigiLockerState string

const (
	DigiLockerPending   DigiLockerState = "pending"
	DigiLockerCompleted DigiLockerState = "completed"
	DigiLockerFailed    DigiLockerState = "failed"
)

// AadhaarRecord is what DigiLocker returns from the driver's Aadhaar.
type AadhaarRecord struct {
	Name        string
	DateOfBirth time.Time
	Gender      Gender // empty when the Aadhaar's value isn't one we know
	Last4       string // the Aadhaar's last 4 digits; the rest comes masked
}

// LicenseRecord is what the transport department holds for a licence.
type LicenseRecord struct {
	Number     string
	Name       string
	ValidUntil time.Time // zero when not given
	Classes    []string  // e.g. LMV, MCWG
}

// BankAccountRecord is what a penny drop learnt about an account.
type BankAccountRecord struct {
	Exists bool
	Name   string // the name the bank holds for the account
}

// KYCReview is one driver in the back office's KYC queue.
type KYCReview struct {
	DriverID    string             `json:"driverId"`
	Phone       string             `json:"phone"`
	Profile     DriverProfile      `json:"profile"`
	BankAccount *DriverBankAccount `json:"bankAccount,omitempty"`
}
