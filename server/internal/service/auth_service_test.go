package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// fakeUserStore is an in-memory UserStore for service tests. Pre-seed byPhone to
// simulate already-registered accounts.
type fakeUserStore struct {
	created   []repository.CreateUserParams
	byPhone   map[string]domain.User // existing accounts, keyed by phone
	createErr error                  // forced CreateUser error
}

func (f *fakeUserStore) CreateUser(_ context.Context, p repository.CreateUserParams) (domain.User, error) {
	if f.createErr != nil {
		return domain.User{}, f.createErr
	}
	f.created = append(f.created, p)
	u := domain.User{
		ID:          "u1",
		PhoneE164:   p.PhoneE164,
		Name:        p.Name,
		Email:       p.Email,
		DateOfBirth: p.DateOfBirth,
		CreatedAt:   time.Now(),
	}
	if f.byPhone == nil {
		f.byPhone = map[string]domain.User{}
	}
	f.byPhone[u.PhoneE164] = u
	return u, nil
}

func (f *fakeUserStore) FindByPhone(_ context.Context, phoneE164 string) (domain.User, error) {
	if u, ok := f.byPhone[phoneE164]; ok {
		return u, nil
	}
	return domain.User{}, repository.ErrUserNotFound
}

func (f *fakeUserStore) FindByID(_ context.Context, id string) (domain.User, error) {
	for _, u := range f.byPhone {
		if u.ID == id {
			return u, nil
		}
	}
	return domain.User{}, repository.ErrUserNotFound
}

func (f *fakeUserStore) ListUsers(context.Context) ([]domain.User, error) {
	return nil, nil
}

// fakeTokenIssuer hands out a fixed token and records the user it was minted for.
type fakeTokenIssuer struct {
	issuedFor []string
	err       error
}

func (f *fakeTokenIssuer) Issue(_ context.Context, userID string) (domain.Session, error) {
	if f.err != nil {
		return domain.Session{}, f.err
	}
	f.issuedFor = append(f.issuedFor, userID)
	return domain.Session{Token: "tok-" + userID, UserID: userID}, nil
}

// fakeOTPSender records calls and returns scripted results.
type fakeOTPSender struct {
	sent      []string
	resent    []string
	verified  []string // "mobile:code"
	verifyOK  bool
	verifyErr error
	sendErr   error
}

func (f *fakeOTPSender) SendOTP(_ context.Context, mobile string) error {
	f.sent = append(f.sent, mobile)
	return f.sendErr
}

func (f *fakeOTPSender) ResendOTP(_ context.Context, mobile string) error {
	f.resent = append(f.resent, mobile)
	return nil
}

func (f *fakeOTPSender) VerifyOTP(_ context.Context, mobile, code string) (bool, error) {
	f.verified = append(f.verified, mobile+":"+code)
	return f.verifyOK, f.verifyErr
}

// fakeLimiter is a scriptable OTPLimiter for asserting the auth service wires
// the guard in correctly.
type fakeLimiter struct {
	begun     []string
	succeeded []string
	resendOK  bool          // Resend result
	retry     time.Duration // Resend retryAfter
	verifyOK  bool          // CheckVerify result
	invalidat bool          // RecordFailure result
	failures  int           // RecordFailure call count
}

func (f *fakeLimiter) Begin(p string)                      { f.begun = append(f.begun, p) }
func (f *fakeLimiter) Resend(string) (bool, time.Duration) { return f.resendOK, f.retry }
func (f *fakeLimiter) CheckVerify(string) bool             { return f.verifyOK }
func (f *fakeLimiter) RecordFailure(string) bool           { f.failures++; return f.invalidat }
func (f *fakeLimiter) Succeed(p string)                    { f.succeeded = append(f.succeeded, p) }

func adultDOB() time.Time { return time.Now().AddDate(-25, 0, 0) }

func TestOTPLimiterWiring(t *testing.T) {
	const phone = "+919876543210"

	t.Run("RequestOTP begins a session", func(t *testing.T) {
		lim := &fakeLimiter{}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim))
		if err := s.RequestOTP(context.Background(), phone); err != nil {
			t.Fatalf("RequestOTP: %v", err)
		}
		if len(lim.begun) != 1 || lim.begun[0] != phone {
			t.Fatalf("expected Begin(%q), got %v", phone, lim.begun)
		}
	})

	t.Run("ResendOTP surfaces a lock as OTPLockedError", func(t *testing.T) {
		lim := &fakeLimiter{resendOK: false, retry: 30 * time.Minute}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim), WithOTPSender(&fakeOTPSender{}))
		err := s.ResendOTP(context.Background(), phone)
		var locked *OTPLockedError
		if !errors.As(err, &locked) {
			t.Fatalf("want *OTPLockedError, got %v", err)
		}
		if locked.RetryAfter != 30*time.Minute {
			t.Fatalf("retryAfter should propagate, got %v", locked.RetryAfter)
		}
	})

	t.Run("ResendOTP dispatches when allowed", func(t *testing.T) {
		sender := &fakeOTPSender{}
		lim := &fakeLimiter{resendOK: true}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim), WithOTPSender(sender))
		if err := s.ResendOTP(context.Background(), phone); err != nil {
			t.Fatalf("ResendOTP: %v", err)
		}
		if len(sender.resent) != 1 {
			t.Fatalf("an allowed resend should reach the provider, got %v", sender.resent)
		}
	})

	t.Run("VerifyOTP rejects an invalidated OTP before the provider", func(t *testing.T) {
		sender := &fakeOTPSender{verifyOK: true}
		lim := &fakeLimiter{verifyOK: false}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim), WithOTPSender(sender))
		_, err := s.VerifyOTP(context.Background(), phone, "123456")
		if !errors.Is(err, ErrOTPInvalidated) {
			t.Fatalf("want ErrOTPInvalidated, got %v", err)
		}
		if len(sender.verified) != 0 {
			t.Fatal("a dead OTP must not be checked against the provider")
		}
	})

	t.Run("a wrong code that hits the cap returns ErrOTPInvalidated", func(t *testing.T) {
		lim := &fakeLimiter{verifyOK: true, invalidat: true}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim), WithOTPSender(&fakeOTPSender{verifyOK: false}))
		_, err := s.VerifyOTP(context.Background(), phone, "000000")
		if !errors.Is(err, ErrOTPInvalidated) {
			t.Fatalf("want ErrOTPInvalidated, got %v", err)
		}
		if lim.failures != 1 {
			t.Fatalf("a wrong code should record one failure, got %d", lim.failures)
		}
	})

	t.Run("a wrong code below the cap stays ErrInvalidOTP", func(t *testing.T) {
		lim := &fakeLimiter{verifyOK: true, invalidat: false}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim), WithOTPSender(&fakeOTPSender{verifyOK: false}))
		_, err := s.VerifyOTP(context.Background(), phone, "000000")
		if !errors.Is(err, ErrInvalidOTP) {
			t.Fatalf("want ErrInvalidOTP, got %v", err)
		}
	})

	t.Run("a correct code clears the session", func(t *testing.T) {
		lim := &fakeLimiter{verifyOK: true}
		s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(lim), WithOTPSender(&fakeOTPSender{verifyOK: true}))
		if _, err := s.VerifyOTP(context.Background(), phone, "654321"); err != nil {
			t.Fatalf("VerifyOTP: %v", err)
		}
		if len(lim.succeeded) != 1 || lim.succeeded[0] != phone {
			t.Fatalf("a correct code should Succeed(%q), got %v", phone, lim.succeeded)
		}
	})
}

func TestVerifyOTP_DevMode(t *testing.T) {
	s := NewAuthService(&fakeUserStore{})

	// Unknown number, correct dev code: passes but reports not-yet-registered.
	res, err := s.VerifyOTP(context.Background(), "+919876543210", DevOTP)
	if err != nil {
		t.Fatalf("correct OTP should pass, got %v", err)
	}
	if res.Registered {
		t.Fatalf("unknown number should be Registered=false, got %+v", res)
	}

	if _, err := s.VerifyOTP(context.Background(), "+919876543210", "000000"); !errors.Is(err, ErrInvalidOTP) {
		t.Fatalf("wrong OTP should be ErrInvalidOTP, got %v", err)
	}
	if _, err := s.VerifyOTP(context.Background(), "12345", DevOTP); !errors.Is(err, ErrInvalidPhone) {
		t.Fatalf("bad phone should be ErrInvalidPhone, got %v", err)
	}
}

func TestVerifyOTP_ExistingNumberLogsIn(t *testing.T) {
	existing := domain.User{ID: "u1", PhoneE164: "+919876543210", Name: "Asha"}
	users := &fakeUserStore{byPhone: map[string]domain.User{existing.PhoneE164: existing}}
	tokens := &fakeTokenIssuer{}
	s := NewAuthService(users, WithTokenIssuer(tokens))

	res, err := s.VerifyOTP(context.Background(), "+919876543210", DevOTP)
	if err != nil {
		t.Fatalf("VerifyOTP: %v", err)
	}
	if !res.Registered {
		t.Fatal("an existing number should be Registered=true")
	}
	if res.User.ID != "u1" {
		t.Fatalf("wrong user returned: %+v", res.User)
	}
	if res.Token != "tok-u1" {
		t.Fatalf("expected a session token, got %q", res.Token)
	}
	if len(tokens.issuedFor) != 1 || tokens.issuedFor[0] != "u1" {
		t.Fatalf("token should be issued for u1, got %v", tokens.issuedFor)
	}
}

func TestRequestAndResendOTP_DelegateToSender(t *testing.T) {
	sender := &fakeOTPSender{}
	s := NewAuthService(&fakeUserStore{}, WithOTPSender(sender))

	if err := s.RequestOTP(context.Background(), "+919876543210"); err != nil {
		t.Fatalf("RequestOTP: %v", err)
	}
	if err := s.ResendOTP(context.Background(), "+919876543210"); err != nil {
		t.Fatalf("ResendOTP: %v", err)
	}

	// The +91 prefix is stripped to the bare 10-digit number providers expect.
	if want := []string{"9876543210"}; len(sender.sent) != 1 || sender.sent[0] != want[0] {
		t.Fatalf("SendOTP got %v, want %v", sender.sent, want)
	}
	if len(sender.resent) != 1 || sender.resent[0] != "9876543210" {
		t.Fatalf("ResendOTP got %v", sender.resent)
	}

	// An invalid number is rejected before touching the provider.
	if err := s.RequestOTP(context.Background(), "0000"); !errors.Is(err, ErrInvalidPhone) {
		t.Fatalf("bad phone should be ErrInvalidPhone, got %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("provider should not be called for a bad number: %v", sender.sent)
	}
}

func TestVerifyOTP_WithSender(t *testing.T) {
	t.Run("valid code passes", func(t *testing.T) {
		sender := &fakeOTPSender{verifyOK: true}
		s := NewAuthService(&fakeUserStore{}, WithOTPSender(sender))
		if _, err := s.VerifyOTP(context.Background(), "+919876543210", "654321"); err != nil {
			t.Fatalf("valid code should pass, got %v", err)
		}
		if want := "9876543210:654321"; len(sender.verified) != 1 || sender.verified[0] != want {
			t.Fatalf("VerifyOTP got %v, want %q", sender.verified, want)
		}
	})

	t.Run("wrong code maps to ErrInvalidOTP", func(t *testing.T) {
		s := NewAuthService(&fakeUserStore{}, WithOTPSender(&fakeOTPSender{verifyOK: false}))
		if _, err := s.VerifyOTP(context.Background(), "+919876543210", "000000"); !errors.Is(err, ErrInvalidOTP) {
			t.Fatalf("want ErrInvalidOTP, got %v", err)
		}
	})

	t.Run("provider failure propagates (not an auth error)", func(t *testing.T) {
		boom := errors.New("provider down")
		s := NewAuthService(&fakeUserStore{}, WithOTPSender(&fakeOTPSender{verifyErr: boom}))
		_, err := s.VerifyOTP(context.Background(), "+919876543210", "654321")
		if !errors.Is(err, boom) {
			t.Fatalf("want provider error, got %v", err)
		}
		if errors.Is(err, ErrInvalidOTP) {
			t.Fatal("a provider outage must not be reported as a wrong code")
		}
	})
}

func TestRegister(t *testing.T) {
	tests := []struct {
		name    string
		params  RegisterParams
		wantErr error
	}{
		{
			name:   "valid",
			params: RegisterParams{PhoneE164: "+919876543210", Name: "Asha", Email: "asha@example.com", DateOfBirth: adultDOB()},
		},
		{
			name:    "bad phone",
			params:  RegisterParams{PhoneE164: "98765", Name: "Asha", Email: "asha@example.com", DateOfBirth: adultDOB()},
			wantErr: ErrInvalidPhone,
		},
		{
			name:    "short name",
			params:  RegisterParams{PhoneE164: "+919876543210", Name: "A", Email: "asha@example.com", DateOfBirth: adultDOB()},
			wantErr: ErrInvalidName,
		},
		{
			name:    "bad email",
			params:  RegisterParams{PhoneE164: "+919876543210", Name: "Asha", Email: "nope", DateOfBirth: adultDOB()},
			wantErr: ErrInvalidEmail,
		},
		{
			name:    "under 18",
			params:  RegisterParams{PhoneE164: "+919876543210", Name: "Asha", Email: "asha@example.com", DateOfBirth: time.Now().AddDate(-10, 0, 0)},
			wantErr: ErrInvalidDOB,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := NewAuthService(&fakeUserStore{}, WithTokenIssuer(&fakeTokenIssuer{}))
			res, err := s.Register(context.Background(), tt.params)
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("want %v, got %v", tt.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !res.Registered || res.User.ID == "" {
				t.Fatalf("expected a persisted, logged-in user, got %+v", res)
			}
			if res.Token == "" {
				t.Fatal("register should issue a session token")
			}
		})
	}
}

func TestRegisterPropagatesPhoneTaken(t *testing.T) {
	s := NewAuthService(&fakeUserStore{createErr: repository.ErrPhoneTaken})
	_, err := s.Register(context.Background(), RegisterParams{
		PhoneE164: "+919876543210", Name: "Asha", Email: "asha@example.com", DateOfBirth: adultDOB(),
	})
	if !errors.Is(err, repository.ErrPhoneTaken) {
		t.Fatalf("want ErrPhoneTaken, got %v", err)
	}
}

func TestCurrentUser(t *testing.T) {
	existing := domain.User{ID: "u1", PhoneE164: "+919876543210", Name: "Asha"}
	s := NewAuthService(&fakeUserStore{byPhone: map[string]domain.User{existing.PhoneE164: existing}})

	got, err := s.CurrentUser(context.Background(), "u1")
	if err != nil {
		t.Fatalf("CurrentUser: %v", err)
	}
	if got.ID != "u1" {
		t.Fatalf("wrong user: %+v", got)
	}
	if _, err := s.CurrentUser(context.Background(), "nope"); !errors.Is(err, repository.ErrUserNotFound) {
		t.Fatalf("unknown id should be ErrUserNotFound, got %v", err)
	}
}
