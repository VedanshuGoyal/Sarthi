package service

import (
	"context"
	"errors"
	"strings"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// DriverStore is the slice of persistence the driver auth service needs.
// Defined here (consumer side) so the service stays testable with a fake, the
// same shape as [UserStore].
type DriverStore interface {
	CreateDriver(ctx context.Context, p repository.CreateDriverParams) (domain.Driver, error)
	FindByPhone(ctx context.Context, phoneE164 string) (domain.Driver, error)
	FindByID(ctx context.Context, id string) (domain.Driver, error)
}

// DriverAuthService implements phone-number registration and login for the
// driver app: request OTP, verify it, then either log an existing driver in or
// create a new one — both paths issue a session token. It mirrors
// [AuthService] but registration only collects a name (drivers chauffeur the
// customer's own car, so there's no email/date-of-birth/vehicle to collect up
// front); vehicle details are filled in later, outside this flow.
type DriverAuthService struct {
	drivers DriverStore
	// otp is the SMS provider. When nil the service runs in dev mode: no SMS is
	// sent and the fixed [DevOTP] is accepted.
	otp OTPSender
	// tokens mints session tokens on login/registration. When nil (dev/tests) no
	// token is issued and [DriverAuthResult.Token] is empty.
	tokens TokenIssuer
	// limiter caps OTP resends/failed verifications. When nil the caps are not
	// enforced (dev/tests).
	limiter OTPLimiter
}

// DriverAuthResult is the outcome of an authentication step (OTP verify or
// register).
type DriverAuthResult struct {
	// Registered reports whether an account exists for the number. After
	// VerifyOTP a false value means the caller should collect a name and call
	// Register; true means Driver and Token are populated (logged in).
	Registered bool
	Driver     domain.Driver
	Token      string
}

// DriverOption configures a [DriverAuthService].
type DriverOption func(*DriverAuthService)

// WithDriverOTPSender wires a real SMS provider. Without it the service
// accepts the fixed [DevOTP].
func WithDriverOTPSender(sender OTPSender) DriverOption {
	return func(s *DriverAuthService) { s.otp = sender }
}

// WithDriverTokenIssuer wires session-token issuance. Without it
// login/registration succeed but return an empty token (dev/tests).
func WithDriverTokenIssuer(t TokenIssuer) DriverOption {
	return func(s *DriverAuthService) { s.tokens = t }
}

// WithDriverOTPLimiter wires OTP abuse limits (resend cap, failed-verification
// cap, lockout). Without it the caps are not enforced.
func WithDriverOTPLimiter(l OTPLimiter) DriverOption {
	return func(s *DriverAuthService) { s.limiter = l }
}

// NewDriverAuthService constructs the service over a driver store. Pass
// [WithDriverOTPSender] to enable real SMS delivery.
func NewDriverAuthService(drivers DriverStore, opts ...DriverOption) *DriverAuthService {
	s := &DriverAuthService{drivers: drivers}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

// RequestOTP validates the number and dispatches a one-time code via the SMS
// provider. In dev mode (no provider) it's a no-op and [DevOTP] is accepted.
func (s *DriverAuthService) RequestOTP(ctx context.Context, phoneE164 string) error {
	if !phoneRe.MatchString(phoneE164) {
		return ErrInvalidPhone
	}
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
func (s *DriverAuthService) ResendOTP(ctx context.Context, phoneE164 string) error {
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
// driver. Returns [ErrInvalidOTP] on a wrong code. When the number already has
// an account, the result carries the driver and a fresh session token
// (Registered=true); when it's new, Registered is false and the caller should
// collect a name and call [Register].
func (s *DriverAuthService) VerifyOTP(ctx context.Context, phoneE164, code string) (DriverAuthResult, error) {
	if !phoneRe.MatchString(phoneE164) {
		return DriverAuthResult{}, ErrInvalidPhone
	}
	if s.limiter != nil && !s.limiter.CheckVerify(phoneE164) {
		return DriverAuthResult{}, ErrOTPInvalidated
	}
	if err := s.checkOTP(ctx, phoneE164, code); err != nil {
		if errors.Is(err, ErrInvalidOTP) && s.limiter != nil {
			if s.limiter.RecordFailure(phoneE164) {
				return DriverAuthResult{}, ErrOTPInvalidated
			}
		}
		return DriverAuthResult{}, err
	}
	if s.limiter != nil {
		s.limiter.Succeed(phoneE164)
	}

	driver, err := s.drivers.FindByPhone(ctx, phoneE164)
	if errors.Is(err, repository.ErrDriverNotFound) {
		return DriverAuthResult{Registered: false}, nil
	}
	if err != nil {
		return DriverAuthResult{}, err
	}
	return s.login(ctx, driver)
}

// checkOTP validates the code against the SMS provider, or the fixed [DevOTP]
// in dev mode (no provider).
func (s *DriverAuthService) checkOTP(ctx context.Context, phoneE164, code string) error {
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

// login builds a logged-in result for driver, issuing a session token.
func (s *DriverAuthService) login(ctx context.Context, driver domain.Driver) (DriverAuthResult, error) {
	token, err := s.issueToken(ctx, driver.ID)
	if err != nil {
		return DriverAuthResult{}, err
	}
	return DriverAuthResult{Registered: true, Driver: driver, Token: token}, nil
}

// issueToken mints a session token, or returns "" when no issuer is wired
// (dev/tests).
func (s *DriverAuthService) issueToken(ctx context.Context, driverID string) (string, error) {
	if s.tokens == nil {
		return "", nil
	}
	sess, err := s.tokens.Issue(ctx, driverID)
	if err != nil {
		return "", err
	}
	return sess.Token, nil
}

// CurrentDriver returns the account for an authenticated driver id (backs
// GET /driver/auth/me). A missing driver surfaces as
// [repository.ErrDriverNotFound].
func (s *DriverAuthService) CurrentDriver(ctx context.Context, driverID string) (domain.Driver, error) {
	return s.drivers.FindByID(ctx, driverID)
}

// DriverRegisterParams is the validated input for creating a driver account.
type DriverRegisterParams struct {
	PhoneE164 string
	Name      string
}

// Register validates the name, persists a new driver account, and logs it in
// (issuing a session token). A duplicate phone number surfaces as
// [repository.ErrDriverPhoneTaken].
func (s *DriverAuthService) Register(ctx context.Context, p DriverRegisterParams) (DriverAuthResult, error) {
	name := strings.TrimSpace(p.Name)

	switch {
	case !phoneRe.MatchString(p.PhoneE164):
		return DriverAuthResult{}, ErrInvalidPhone
	case len(name) < 2:
		return DriverAuthResult{}, ErrInvalidName
	}

	driver, err := s.drivers.CreateDriver(ctx, repository.CreateDriverParams{
		PhoneE164: p.PhoneE164,
		Name:      name,
	})
	if err != nil {
		return DriverAuthResult{}, err
	}
	return s.login(ctx, driver)
}
