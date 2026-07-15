// Package service holds business logic. It validates input, orchestrates
// repositories, and is transport-agnostic (no HTTP/JSON concerns leak in).
package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// DevOTP is the fixed one-time passcode accepted until a real SMS provider is
// wired up. OTPLength is the number of digits the apps collect.
const (
	DevOTP    = "123456"
	OTPLength = 6
	minAge    = 18
)

// Validation / flow errors. Handlers map these to HTTP status codes.
var (
	ErrInvalidPhone = errors.New("enter a valid +91 mobile number")
	ErrInvalidName  = errors.New("enter a valid name")
	ErrInvalidEmail = errors.New("enter a valid email address")
	ErrInvalidDOB   = fmt.Errorf("you must be at least %d years old", minAge)
	ErrInvalidOTP   = errors.New("incorrect verification code")
	// ErrOTPInvalidated means too many wrong codes were entered; the current OTP
	// is dead and the user must request a new one (restart the flow).
	ErrOTPInvalidated = errors.New("too many incorrect attempts; request a new code")
)

// OTPLockedError reports that OTP resends are temporarily blocked after the
// resend cap was hit. RetryAfter is how long until they're allowed again; the
// user can also restart the flow to get a fresh code immediately.
type OTPLockedError struct {
	RetryAfter time.Duration
}

func (e *OTPLockedError) Error() string {
	mins := int(e.RetryAfter.Minutes() + 0.5)
	return fmt.Sprintf("too many code requests; try again in %d minutes or restart", mins)
}

var (
	phoneRe = regexp.MustCompile(`^\+91[6-9]\d{9}$`)
	emailRe = regexp.MustCompile(`^[\w.+-]+@[\w-]+\.[\w.-]+$`)
)

// UserStore is the slice of persistence the auth service needs. Defining it
// here (consumer side) keeps the service testable with a fake.
type UserStore interface {
	CreateUser(ctx context.Context, p repository.CreateUserParams) (domain.User, error)
	FindByPhone(ctx context.Context, phoneE164 string) (domain.User, error)
	FindByID(ctx context.Context, id string) (domain.User, error)
	ListUsers(ctx context.Context) ([]domain.User, error)
}

// TokenIssuer mints an auth session for a user. Consumer-side interface so the
// service is decoupled from the session mechanism ([SessionService]).
type TokenIssuer interface {
	Issue(ctx context.Context, userID string) (domain.Session, error)
}

// OTPSender is the outbound SMS provider the auth service drives. It's defined
// consumer-side (like [UserStore]) so the service stays testable with a fake
// and independent of any particular vendor (Fast2SMS today). Numbers are passed
// as bare 10-digit national mobile numbers.
//
// VerifyOTP distinguishes a wrong/expired code (ok=false, err=nil) from a
// provider failure (err != nil), letting the service map only the former to
// [ErrInvalidOTP].
type OTPSender interface {
	SendOTP(ctx context.Context, mobile string) error
	VerifyOTP(ctx context.Context, mobile, code string) (ok bool, err error)
	ResendOTP(ctx context.Context, mobile string) error
}

// OTPLimiter guards an OTP session against abuse — capping resends and failed
// verifications and enforcing a lockout. It's a consumer-side interface (like
// [OTPSender]) so the service stays testable with a fake; it's satisfied by
// memstore.OTPGuard. Phone numbers are passed in full E.164 form. When no
// limiter is wired the caps are simply not enforced.
type OTPLimiter interface {
	// Begin starts (or restarts) a session, clearing all counters and locks.
	Begin(phoneE164 string)
	// Resend counts a resend; ok=false (with retryAfter) means it's locked.
	Resend(phoneE164 string) (ok bool, retryAfter time.Duration)
	// CheckVerify reports whether a verification may proceed (OTP not yet dead).
	CheckVerify(phoneE164 string) bool
	// RecordFailure counts a wrong code; invalidated=true kills the OTP.
	RecordFailure(phoneE164 string) (invalidated bool)
	// Succeed clears a session after a correct code.
	Succeed(phoneE164 string)
}

// AuthService implements phone-number registration and login: request OTP,
// verify it, then either log an existing account in or create a new one — both
// paths issue a session token.
type AuthService struct {
	users UserStore
	// otp is the SMS provider. When nil the service runs in dev mode: no SMS is
	// sent and the fixed [DevOTP] is accepted, so local runs and CI need no
	// provider credentials.
	otp OTPSender
	// tokens mints session tokens on login/registration. When nil (dev/tests)
	// no token is issued and [AuthResult.Token] is empty.
	tokens TokenIssuer
	// limiter caps OTP resends/failed verifications. When nil the caps are not
	// enforced (dev/tests).
	limiter OTPLimiter
}

// AuthResult is the outcome of an authentication step (OTP verify or register).
type AuthResult struct {
	// Registered reports whether an account exists for the number. After
	// VerifyOTP a false value means the caller should collect a profile and call
	// Register; true means User and Token are populated (logged in).
	Registered bool
	User       domain.User
	Token      string
}

// Option configures an [AuthService].
type Option func(*AuthService)

// WithOTPSender wires a real SMS provider. Without it the service accepts the
// fixed [DevOTP].
func WithOTPSender(sender OTPSender) Option {
	return func(s *AuthService) { s.otp = sender }
}

// WithTokenIssuer wires session-token issuance. Without it login/registration
// succeed but return an empty token (dev/tests).
func WithTokenIssuer(t TokenIssuer) Option {
	return func(s *AuthService) { s.tokens = t }
}

// WithOTPLimiter wires OTP abuse limits (resend cap, failed-verification cap,
// lockout). Without it the caps are not enforced.
func WithOTPLimiter(l OTPLimiter) Option {
	return func(s *AuthService) { s.limiter = l }
}

// NewAuthService constructs the service over a user store. Pass
// [WithOTPSender] to enable real SMS delivery.
func NewAuthService(users UserStore, opts ...Option) *AuthService {
	s := &AuthService{users: users}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

// RequestOTP validates the number and dispatches a one-time code via the SMS
// provider. In dev mode (no provider) it's a no-op and [DevOTP] is accepted.
func (s *AuthService) RequestOTP(ctx context.Context, phoneE164 string) error {
	if !phoneRe.MatchString(phoneE164) {
		return ErrInvalidPhone
	}
	// A fresh code starts a fresh session — this is also how a user "restarts"
	// out of a lockout or an invalidated OTP.
	if s.limiter != nil {
		s.limiter.Begin(phoneE164)
	}
	if s.otp == nil {
		return nil
	}
	return s.otp.SendOTP(ctx, nationalMobile(phoneE164))
}

// ResendOTP re-sends the most recent code to the number. In dev mode it's a
// no-op ([DevOTP] remains valid).
func (s *AuthService) ResendOTP(ctx context.Context, phoneE164 string) error {
	if !phoneRe.MatchString(phoneE164) {
		return ErrInvalidPhone
	}
	if s.limiter != nil {
		if ok, retryAfter := s.limiter.Resend(phoneE164); !ok {
			return &OTPLockedError{RetryAfter: retryAfter}
		}
	}
	if s.otp == nil {
		return nil
	}
	return s.otp.ResendOTP(ctx, nationalMobile(phoneE164))
}

// VerifyOTP checks the code for a number and, on success, logs in an existing
// account. Returns [ErrInvalidOTP] on a wrong code. When the number already has
// an account, the result carries the user and a fresh session token
// (Registered=true); when it's new, Registered is false and the caller should
// collect a profile and call [Register].
func (s *AuthService) VerifyOTP(ctx context.Context, phoneE164, code string) (AuthResult, error) {
	if !phoneRe.MatchString(phoneE164) {
		return AuthResult{}, ErrInvalidPhone
	}
	// Reject up front once the OTP has been killed by too many wrong codes, so a
	// dead code never reaches the provider.
	if s.limiter != nil && !s.limiter.CheckVerify(phoneE164) {
		return AuthResult{}, ErrOTPInvalidated
	}
	if err := s.checkOTP(ctx, phoneE164, code); err != nil {
		// Count only genuine wrong codes, not provider outages. Hitting the cap
		// invalidates the OTP.
		if errors.Is(err, ErrInvalidOTP) && s.limiter != nil {
			if s.limiter.RecordFailure(phoneE164) {
				return AuthResult{}, ErrOTPInvalidated
			}
		}
		return AuthResult{}, err
	}
	if s.limiter != nil {
		s.limiter.Succeed(phoneE164)
	}

	user, err := s.users.FindByPhone(ctx, phoneE164)
	if errors.Is(err, repository.ErrUserNotFound) {
		return AuthResult{Registered: false}, nil
	}
	if err != nil {
		return AuthResult{}, err
	}
	return s.login(ctx, user)
}

// checkOTP validates the code against the SMS provider, or the fixed [DevOTP] in
// dev mode (no provider).
func (s *AuthService) checkOTP(ctx context.Context, phoneE164, code string) error {
	if s.otp == nil {
		if code != DevOTP {
			return ErrInvalidOTP
		}
		return nil
	}
	ok, err := s.otp.VerifyOTP(ctx, nationalMobile(phoneE164), code)
	if err != nil {
		return err
	}
	if !ok {
		return ErrInvalidOTP
	}
	return nil
}

// login builds a logged-in result for user, issuing a session token.
func (s *AuthService) login(ctx context.Context, user domain.User) (AuthResult, error) {
	token, err := s.issueToken(ctx, user.ID)
	if err != nil {
		return AuthResult{}, err
	}
	return AuthResult{Registered: true, User: user, Token: token}, nil
}

// issueToken mints a session token, or returns "" when no issuer is wired
// (dev/tests).
func (s *AuthService) issueToken(ctx context.Context, userID string) (string, error) {
	if s.tokens == nil {
		return "", nil
	}
	sess, err := s.tokens.Issue(ctx, userID)
	if err != nil {
		return "", err
	}
	return sess.Token, nil
}

// CurrentUser returns the account for an authenticated user id (backs
// GET /auth/me). A missing user surfaces as [repository.ErrUserNotFound].
func (s *AuthService) CurrentUser(ctx context.Context, userID string) (domain.User, error) {
	return s.users.FindByID(ctx, userID)
}

// nationalMobile strips the +91 country code, leaving the bare 10-digit number
// SMS providers expect. Callers pass numbers already matched by [phoneRe], so
// the prefix is always present.
func nationalMobile(phoneE164 string) string {
	return strings.TrimPrefix(phoneE164, "+91")
}

// RegisterParams is the validated input for creating an account.
type RegisterParams struct {
	PhoneE164   string
	Name        string
	Email       string
	DateOfBirth time.Time
}

// Register validates the profile, persists a new account, and logs it in
// (issuing a session token). A duplicate phone number surfaces as
// [repository.ErrPhoneTaken].
func (s *AuthService) Register(ctx context.Context, p RegisterParams) (AuthResult, error) {
	name := strings.TrimSpace(p.Name)
	email := strings.TrimSpace(p.Email)

	switch {
	case !phoneRe.MatchString(p.PhoneE164):
		return AuthResult{}, ErrInvalidPhone
	case len(name) < 2:
		return AuthResult{}, ErrInvalidName
	case !emailRe.MatchString(email):
		return AuthResult{}, ErrInvalidEmail
	case !isAdult(p.DateOfBirth):
		return AuthResult{}, ErrInvalidDOB
	}

	user, err := s.users.CreateUser(ctx, repository.CreateUserParams{
		PhoneE164:   p.PhoneE164,
		Name:        name,
		Email:       email,
		DateOfBirth: p.DateOfBirth,
	})
	if err != nil {
		return AuthResult{}, err
	}
	return s.login(ctx, user)
}

// ListUsers returns all registered accounts (admin/diagnostic).
func (s *AuthService) ListUsers(ctx context.Context) ([]domain.User, error) {
	return s.users.ListUsers(ctx)
}

// isAdult reports whether dob is in the past and at least minAge years ago.
func isAdult(dob time.Time) bool {
	if dob.IsZero() {
		return false
	}
	now := time.Now()
	if !dob.Before(now) {
		return false
	}
	eighteenth := dob.AddDate(minAge, 0, 0)
	return !eighteenth.After(now)
}
