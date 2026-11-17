package service

import (
	"context"
	"errors"
	"testing"

	"github.com/sarthi/server/internal/memstore"
)

// HUMAN REVIEW REQUIRED: auth. The registration ticket, end to end over the
// real OTP guard, for both apps: a build that sends it must, an attacker who
// only knows the number can't spend the pass of a client that verified with
// one, and older builds keep the phone-only pass.
func TestRegistrationTicket(t *testing.T) {
	ctx := context.Background()
	const phone = "+919876543210"
	type flow struct {
		verify   func(ticketClient bool) (ticket string, err error)
		register func(ticket string, required bool) error
	}
	flows := map[string]func() flow{
		"customer": func() flow {
			s := NewAuthService(&fakeUserStore{}, WithOTPLimiter(memstore.NewOTPGuard()))
			return flow{
				verify: func(tc bool) (string, error) {
					res, err := s.VerifyOTP(ctx, phone, DevOTP, tc)
					return res.RegistrationTicket, err
				},
				register: func(ticket string, required bool) error {
					_, err := s.Register(ctx, RegisterParams{
						PhoneE164: phone, Name: "Asha", Email: "asha@example.com", DateOfBirth: adultDOB(),
						RegistrationTicket: ticket, TicketRequired: required,
					})
					return err
				},
			}
		},
		"driver": func() flow {
			s := NewDriverAuthService(&fakeDriverStore{}, WithDriverOTPLimiter(memstore.NewOTPGuard()))
			return flow{
				verify: func(tc bool) (string, error) {
					res, err := s.VerifyOTP(ctx, phone, DevOTP, tc)
					return res.RegistrationTicket, err
				},
				register: func(ticket string, required bool) error {
					_, err := s.Register(ctx, DriverRegisterParams{
						PhoneE164: phone, Name: "Ravi Kumar", RegistrationTicket: ticket, TicketRequired: required,
					})
					return err
				},
			}
		},
	}
	for name, newFlow := range flows {
		t.Run(name+": a ticket build registers with its ticket only", func(t *testing.T) {
			f := newFlow()
			ticket, err := f.verify(true)
			if err != nil || ticket == "" {
				t.Fatalf("verify: ticket %q, %v", ticket, err)
			}
			// The attacker polls with no headers and no ticket, or a guess.
			if err := f.register("", false); !errors.Is(err, ErrOTPNotVerified) {
				t.Errorf("phone-only register: err = %v, want ErrOTPNotVerified", err)
			}
			if err := f.register("guess", false); !errors.Is(err, ErrOTPNotVerified) {
				t.Errorf("wrong ticket: err = %v, want ErrOTPNotVerified", err)
			}
			if err := f.register("", true); !errors.Is(err, ErrOTPNotVerified) {
				t.Errorf("ticket build without its ticket: err = %v, want ErrOTPNotVerified", err)
			}
			if err := f.register(ticket, true); err != nil {
				t.Errorf("register with the ticket: %v", err)
			}
		})
		t.Run(name+": an older build keeps the phone-only pass", func(t *testing.T) {
			f := newFlow()
			if _, err := f.verify(false); err != nil {
				t.Fatalf("verify: %v", err)
			}
			if err := f.register("", false); err != nil {
				t.Errorf("phone-only register: %v", err)
			}
		})
		t.Run(name+": a ticket build's register needs a ticket whoever verified", func(t *testing.T) {
			f := newFlow()
			if _, err := f.verify(false); err != nil {
				t.Fatalf("verify: %v", err)
			}
			if err := f.register("", true); !errors.Is(err, ErrOTPNotVerified) {
				t.Errorf("err = %v, want ErrOTPNotVerified", err)
			}
		})
	}
}
