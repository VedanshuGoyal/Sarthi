package service

import (
	"context"
	"errors"
	"testing"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// fakeDriverStore is an in-memory DriverStore for service tests, mirroring
// fakeUserStore.
type fakeDriverStore struct {
	created   []repository.CreateDriverParams
	byPhone   map[string]domain.Driver // existing accounts, keyed by phone
	createErr error                    // forced CreateDriver error
}

func (f *fakeDriverStore) CreateDriver(_ context.Context, p repository.CreateDriverParams) (domain.Driver, error) {
	if f.createErr != nil {
		return domain.Driver{}, f.createErr
	}
	f.created = append(f.created, p)
	d := domain.Driver{ID: "d1", PhoneE164: p.PhoneE164, Name: p.Name}
	if f.byPhone == nil {
		f.byPhone = map[string]domain.Driver{}
	}
	f.byPhone[d.PhoneE164] = d
	return d, nil
}

func (f *fakeDriverStore) FindByPhone(_ context.Context, phoneE164 string) (domain.Driver, error) {
	if d, ok := f.byPhone[phoneE164]; ok {
		return d, nil
	}
	return domain.Driver{}, repository.ErrDriverNotFound
}

func (f *fakeDriverStore) FindByID(_ context.Context, id string) (domain.Driver, error) {
	for _, d := range f.byPhone {
		if d.ID == id {
			return d, nil
		}
	}
	return domain.Driver{}, repository.ErrDriverNotFound
}

func TestDriverVerifyOTP_DevMode(t *testing.T) {
	s := NewDriverAuthService(&fakeDriverStore{})

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

func TestDriverVerifyOTP_ExistingNumberLogsIn(t *testing.T) {
	existing := domain.Driver{ID: "d1", PhoneE164: "+919876543210", Name: "Ravi"}
	drivers := &fakeDriverStore{byPhone: map[string]domain.Driver{existing.PhoneE164: existing}}
	tokens := &fakeTokenIssuer{}
	s := NewDriverAuthService(drivers, WithDriverTokenIssuer(tokens))

	res, err := s.VerifyOTP(context.Background(), "+919876543210", DevOTP)
	if err != nil {
		t.Fatalf("VerifyOTP: %v", err)
	}
	if !res.Registered {
		t.Fatal("an existing number should be Registered=true")
	}
	if res.Driver.ID != "d1" {
		t.Fatalf("wrong driver returned: %+v", res.Driver)
	}
	if res.Token != "tok-d1" {
		t.Fatalf("expected a session token, got %q", res.Token)
	}
	if len(tokens.issuedFor) != 1 || tokens.issuedFor[0] != "d1" {
		t.Fatalf("token should be issued for d1, got %v", tokens.issuedFor)
	}
}

func TestDriverOTPLimiterWiring(t *testing.T) {
	const phone = "+919876543210"

	t.Run("RequestOTP begins a session", func(t *testing.T) {
		lim := &fakeLimiter{}
		s := NewDriverAuthService(&fakeDriverStore{}, WithDriverOTPLimiter(lim))
		if err := s.RequestOTP(context.Background(), phone); err != nil {
			t.Fatalf("RequestOTP: %v", err)
		}
		if len(lim.begun) != 1 || lim.begun[0] != phone {
			t.Fatalf("expected Begin(%q), got %v", phone, lim.begun)
		}
	})

	t.Run("ResendOTP surfaces a lock as OTPLockedError", func(t *testing.T) {
		lim := &fakeLimiter{resendOK: false}
		s := NewDriverAuthService(&fakeDriverStore{}, WithDriverOTPLimiter(lim), WithDriverOTPSender(&fakeOTPSender{}))
		err := s.ResendOTP(context.Background(), phone)
		var locked *OTPLockedError
		if !errors.As(err, &locked) {
			t.Fatalf("want *OTPLockedError, got %v", err)
		}
	})

	t.Run("VerifyOTP rejects an invalidated OTP before the provider", func(t *testing.T) {
		sender := &fakeOTPSender{verifyOK: true}
		lim := &fakeLimiter{verifyOK: false}
		s := NewDriverAuthService(&fakeDriverStore{}, WithDriverOTPLimiter(lim), WithDriverOTPSender(sender))
		_, err := s.VerifyOTP(context.Background(), phone, "123456")
		if !errors.Is(err, ErrOTPInvalidated) {
			t.Fatalf("want ErrOTPInvalidated, got %v", err)
		}
		if len(sender.verified) != 0 {
			t.Fatal("a dead OTP must not be checked against the provider")
		}
	})
}

func TestDriverRegister(t *testing.T) {
	tests := []struct {
		name    string
		params  DriverRegisterParams
		wantErr error
	}{
		{
			name:   "valid",
			params: DriverRegisterParams{PhoneE164: "+919876543210", Name: "Ravi"},
		},
		{
			name:    "bad phone",
			params:  DriverRegisterParams{PhoneE164: "98765", Name: "Ravi"},
			wantErr: ErrInvalidPhone,
		},
		{
			name:    "short name",
			params:  DriverRegisterParams{PhoneE164: "+919876543210", Name: "R"},
			wantErr: ErrInvalidName,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := NewDriverAuthService(&fakeDriverStore{}, WithDriverTokenIssuer(&fakeTokenIssuer{}))
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
			if !res.Registered || res.Driver.ID == "" {
				t.Fatalf("expected a persisted, logged-in driver, got %+v", res)
			}
			if res.Token == "" {
				t.Fatal("register should issue a session token")
			}
		})
	}
}

func TestDriverRegisterPropagatesPhoneTaken(t *testing.T) {
	s := NewDriverAuthService(&fakeDriverStore{createErr: repository.ErrDriverPhoneTaken})
	_, err := s.Register(context.Background(), DriverRegisterParams{PhoneE164: "+919876543210", Name: "Ravi"})
	if !errors.Is(err, repository.ErrDriverPhoneTaken) {
		t.Fatalf("want ErrDriverPhoneTaken, got %v", err)
	}
}

func TestCurrentDriver(t *testing.T) {
	existing := domain.Driver{ID: "d1", PhoneE164: "+919876543210", Name: "Ravi"}
	s := NewDriverAuthService(&fakeDriverStore{byPhone: map[string]domain.Driver{existing.PhoneE164: existing}})

	got, err := s.CurrentDriver(context.Background(), "d1")
	if err != nil {
		t.Fatalf("CurrentDriver: %v", err)
	}
	if got.ID != "d1" {
		t.Fatalf("wrong driver: %+v", got)
	}
	if _, err := s.CurrentDriver(context.Background(), "nope"); !errors.Is(err, repository.ErrDriverNotFound) {
		t.Fatalf("unknown id should be ErrDriverNotFound, got %v", err)
	}
}
