package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/memstore"
)

// The day's SMS budget is shared by both apps and counts only texts that
// are actually sent: a request the number's own guard refuses costs
// nothing, and once the budget is spent no provider call is made.
func TestBudgetedOTPSender_sharedAndCountsOnlySentTexts(t *testing.T) {
	ctx := context.Background()
	budget := memstore.NewSMSBudget(memstore.MaxOTPSends+2, 24*time.Hour)
	customerSMS, driverSMS := &fakeOTPSender{}, &fakeOTPSender{}
	customers := NewAuthService(&fakeUserStore{},
		WithOTPLimiter(memstore.NewOTPGuard()), WithOTPSender(BudgetedOTPSender(customerSMS, budget)))
	drivers := NewDriverAuthService(&fakeDriverStore{},
		WithDriverOTPLimiter(memstore.NewOTPGuard()), WithDriverOTPSender(BudgetedOTPSender(driverSMS, budget)))

	// One number hammered past its own cap, and a malformed one: only the
	// texts the guard let through are spent.
	for range memstore.MaxOTPSends + 3 {
		_ = customers.RequestOTP(ctx, "+919876543210")
	}
	if err := customers.RequestOTP(ctx, "12345"); !errors.Is(err, ErrInvalidPhone) {
		t.Fatalf("bad number: %v", err)
	}
	if got := len(customerSMS.sent); got != memstore.MaxOTPSends {
		t.Fatalf("customer texts = %d, want %d", got, memstore.MaxOTPSends)
	}
	// The driver app spends from the same budget: two texts left.
	for _, phone := range []string{"+919876543211", "+919876543212"} {
		if err := drivers.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("driver send to %s: %v", phone, err)
		}
	}

	err := customers.RequestOTP(ctx, "+919876543213")
	budgetErr, ok := errors.AsType[*SMSBudgetError](err)
	if !ok || budgetErr.RetryAfter <= 0 {
		t.Fatalf("customer send over budget: err = %v, want an SMSBudgetError", err)
	}
	if got := len(customerSMS.sent); got != memstore.MaxOTPSends {
		t.Errorf("customer texts = %d: an over-budget send reached the provider", got)
	}
	if err := drivers.ResendOTP(ctx, "+919876543211"); !errors.As(err, &budgetErr) {
		t.Errorf("driver resend over budget: err = %v, want an SMSBudgetError", err)
	}
	if len(driverSMS.resent) != 0 {
		t.Error("an over-budget resend reached the provider")
	}
}
