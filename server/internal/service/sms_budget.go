package service

import (
	"context"
	"fmt"
	"log/slog"
	"time"
)

// SMSBudget is the service-wide cap on texts sent (memstore.SMSBudget).
type SMSBudget interface {
	// Spend takes one text; ok=false (with retryAfter) means none are left.
	Spend() (ok bool, retryAfter time.Duration)
}

// SMSBudgetError means the service has sent its SMS allowance for the day;
// RetryAfter is when the next window opens.
type SMSBudgetError struct {
	RetryAfter time.Duration
}

func (e *SMSBudgetError) Error() string {
	return fmt.Sprintf("the SMS budget is used up; it resets in %s", e.RetryAfter.Round(time.Minute))
}

// BudgetedOTPSender spends from budget for every code it sends or re-sends,
// then hands the text to sender. Wrap the customer and driver services'
// senders with one budget to share the day's SMS spend: since the services
// only call the sender after a number's own guard allows a send, only texts
// actually dispatched are counted. Verifying a code costs nothing.
func BudgetedOTPSender(sender OTPSender, budget SMSBudget) OTPSender {
	return budgetedSender{OTPSender: sender, budget: budget}
}

type budgetedSender struct {
	OTPSender
	budget SMSBudget
}

func (b budgetedSender) SendOTP(ctx context.Context, mobile string) error {
	if err := b.spend(ctx); err != nil {
		return err
	}
	return b.OTPSender.SendOTP(ctx, mobile)
}

func (b budgetedSender) ResendOTP(ctx context.Context, mobile string) error {
	if err := b.spend(ctx); err != nil {
		return err
	}
	return b.OTPSender.ResendOTP(ctx, mobile)
}

func (b budgetedSender) spend(ctx context.Context) error {
	if ok, retry := b.budget.Spend(); !ok {
		slog.ErrorContext(ctx, "otp: daily SMS budget exhausted; no code sent", "retryAfter", retry.Round(time.Minute).String())
		return &SMSBudgetError{RetryAfter: retry}
	}
	return nil
}
