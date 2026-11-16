package service

import (
	"context"
	"errors"
	"testing"
)

// The consent version the app showed is stored with the account; old builds
// send none and still register, recorded as no consent.
func TestRegister_RecordsConsentVersion(t *testing.T) {
	for _, version := range []string{"2026-11", ""} {
		store := &fakeUserStore{}
		s := NewAuthService(store, WithTokenIssuer(&fakeTokenIssuer{}))
		_, err := s.Register(context.Background(), RegisterParams{
			PhoneE164: "+919876543210", Name: "Asha", Email: "asha@example.com", DateOfBirth: adultDOB(),
			ConsentVersion: version,
		})
		if err != nil {
			t.Fatalf("consent %q: %v", version, err)
		}
		if len(store.created) != 1 || store.created[0].ConsentVersion != version {
			t.Errorf("consent %q: stored %+v", version, store.created)
		}
	}
}

func TestDriverRegister_RecordsConsentVersion(t *testing.T) {
	for _, version := range []string{"2026-11", ""} {
		store := &fakeDriverStore{}
		s := NewDriverAuthService(store, WithDriverTokenIssuer(&fakeTokenIssuer{}))
		_, err := s.Register(context.Background(), DriverRegisterParams{
			PhoneE164: "+919876543210", Name: "Ravi", ConsentVersion: version,
		})
		if err != nil {
			t.Fatalf("consent %q: %v", version, err)
		}
		if len(store.created) != 1 || store.created[0].ConsentVersion != version {
			t.Errorf("consent %q: stored %+v", version, store.created)
		}
	}
}

func TestRegister_RefusesAJunkConsentVersion(t *testing.T) {
	for _, version := range []string{"<script>", "2026 11", "-x", string(make([]byte, 40))} {
		users, drivers := &fakeUserStore{}, &fakeDriverStore{}
		_, err := NewAuthService(users).Register(context.Background(), RegisterParams{
			PhoneE164: "+919876543210", Name: "Asha", Email: "asha@example.com", DateOfBirth: adultDOB(),
			ConsentVersion: version,
		})
		if !errors.Is(err, ErrInvalidConsent) {
			t.Errorf("customer, consent %q: err = %v, want ErrInvalidConsent", version, err)
		}
		_, err = NewDriverAuthService(drivers).Register(context.Background(), DriverRegisterParams{
			PhoneE164: "+919876543210", Name: "Ravi", ConsentVersion: version,
		})
		if !errors.Is(err, ErrInvalidConsent) {
			t.Errorf("driver, consent %q: err = %v, want ErrInvalidConsent", version, err)
		}
		if len(users.created)+len(drivers.created) != 0 {
			t.Errorf("consent %q: an account was created", version)
		}
	}
}
