package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// ErrPaymentsOff is returned when no payment gateway is configured.
var ErrPaymentsOff = errors.New("payments aren't set up yet")

// ErrNotPayable is returned when a customer tries to pay for a ride that
// isn't completed, or has no fare to pay.
var ErrNotPayable = fmt.Errorf("you can pay for a ride once it's completed: %w",
	repository.ErrBookingStateConflict)

// ErrAlreadyPaid is returned when a customer tries to pay for a ride they
// have already paid for.
var ErrAlreadyPaid = fmt.Errorf("this ride is already paid for: %w",
	repository.ErrBookingStateConflict)

const (
	// orderLifetime is how long a checkout stays open at the gateway.
	orderLifetime = 15 * time.Minute

	// minPaymentPaise is the smallest order the gateway takes (₹1).
	minPaymentPaise = 100

	// sweepEvery is how often orders still pending are re-checked, for
	// customers who closed the app mid-payment and webhooks that never came.
	sweepEvery = 2 * time.Minute

	// sweepWindow is how far back the sweep looks; sweepMinAge leaves an
	// order alone until the customer has had a moment with it.
	sweepWindow = 24 * time.Hour
	sweepMinAge = time.Minute
)

// PaymentGateway is the slice of the gateway this service drives
// (payment/phonepe today).
type PaymentGateway interface {
	Name() string
	MerchantID() string
	Environment() string
	CreateOrder(ctx context.Context, merchantOrderID string, amountPaise int64, expireAfter time.Duration) (domain.GatewayOrder, error)
	OrderStatus(ctx context.Context, merchantOrderID string) (domain.GatewayOrderStatus, error)
}

// PaymentStore persists orders and the paid state of bookings
// (repository.PaymentRepository).
type PaymentStore interface {
	InsertOrder(ctx context.Context, o domain.PaymentOrder) error
	FindOrder(ctx context.Context, merchantOrderID string) (domain.PaymentOrder, error)
	PendingForBooking(ctx context.Context, bookingID string) ([]domain.PaymentOrder, error)
	PendingSince(ctx context.Context, from, to time.Time) ([]domain.PaymentOrder, error)
	FailOrder(ctx context.Context, merchantOrderID string, st domain.GatewayOrderStatus, at time.Time) error
	CompleteOrder(ctx context.Context, o domain.PaymentOrder, st domain.GatewayOrderStatus, commissionPaise int64, at time.Time) (domain.SettleOutcome, domain.Booking, error)
}

// CustomerBookingFinder reads one of a customer's bookings
// (repository.BookingRepository).
type CustomerBookingFinder interface {
	FindForUser(ctx context.Context, id, userID string) (domain.UserBooking, error)
}

// PaymentAlerter tells a driver their customer paid (NotifyService).
type PaymentAlerter interface {
	PaymentReceived(ctx context.Context, b domain.Booking)
}

// PaymentService takes the customer's UPI payment for a completed ride.
// MOJUD is paid the whole fare and keeps CommissionBasisPoints of it; the
// rest is owed to the driver until a payout (PayoutService).
//
// The gateway's order-status API is the only proof of payment: a webhook, the
// app coming back from the checkout, and a background sweep are all just
// reasons to go and ask it.
type PaymentService struct {
	gateway  PaymentGateway
	store    PaymentStore
	bookings CustomerBookingFinder
	alerts   PaymentAlerter
	// commissionBP is MOJUD's cut in basis points (1500 = 15%).
	commissionBP int64
	now          func() time.Time
}

// NewPaymentService wires the service. gateway nil turns payments off;
// alerts nil sends no pushes.
func NewPaymentService(gateway PaymentGateway, store PaymentStore, bookings CustomerBookingFinder, alerts PaymentAlerter, commissionBP int64) *PaymentService {
	return &PaymentService{
		gateway:      gateway,
		store:        store,
		bookings:     bookings,
		alerts:       alerts,
		commissionBP: commissionBP,
		now:          time.Now,
	}
}

// Enabled reports whether a gateway is configured.
func (s *PaymentService) Enabled() bool { return s.gateway != nil }

// Checkout opens a UPI checkout for userID's completed booking and returns
// what the app hands the gateway's SDK. A checkout the customer already
// paid through is found first, so paying twice is refused with
// [ErrAlreadyPaid] rather than charged.
func (s *PaymentService) Checkout(ctx context.Context, userID, bookingID string) (domain.PaymentCheckout, error) {
	if s.gateway == nil {
		return domain.PaymentCheckout{}, ErrPaymentsOff
	}
	ub, err := s.bookings.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return domain.PaymentCheckout{}, err
	}
	b := ub.Booking
	if b.Status != domain.RideStatusCompleted {
		return domain.PaymentCheckout{}, ErrNotPayable
	}
	paid := b.PaidAt != nil
	if !paid {
		// A checkout from an earlier tap may have gone through meanwhile.
		if paid, err = s.syncBooking(ctx, b.ID); err != nil {
			return domain.PaymentCheckout{}, err
		}
	}
	if paid {
		return domain.PaymentCheckout{}, ErrAlreadyPaid
	}
	amount := b.FarePaise
	if amount < minPaymentPaise {
		return domain.PaymentCheckout{}, ErrNotPayable
	}

	now := s.now()
	merchantOrderID := newMerchantOrderID(b.ID, now)
	order, err := s.gateway.CreateOrder(ctx, merchantOrderID, amount, orderLifetime)
	if err != nil {
		return domain.PaymentCheckout{}, err
	}
	if err := s.store.InsertOrder(ctx, domain.PaymentOrder{
		MerchantOrderID: merchantOrderID,
		BookingID:       b.ID,
		UserID:          userID,
		AmountPaise:     amount,
		ProviderOrderID: order.ProviderOrderID,
		ExpiresAt:       order.ExpiresAt,
	}); err != nil {
		return domain.PaymentCheckout{}, err
	}
	slog.InfoContext(ctx, "payment: checkout opened",
		"bookingId", b.ID, "userId", userID, "merchantOrderId", merchantOrderID, "amountPaise", amount)
	return domain.PaymentCheckout{
		Provider:        s.gateway.Name(),
		Environment:     s.gateway.Environment(),
		MerchantID:      s.gateway.MerchantID(),
		OrderID:         order.ProviderOrderID,
		Token:           order.Token,
		MerchantOrderID: merchantOrderID,
		AmountPaise:     amount,
		ExpiresAt:       order.ExpiresAt,
	}, nil
}

// Sync re-checks userID's booking's open checkouts with the gateway — the
// app calls it on coming back from the payment page.
func (s *PaymentService) Sync(ctx context.Context, userID, bookingID string) error {
	if s.gateway == nil {
		return ErrPaymentsOff
	}
	ub, err := s.bookings.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return err
	}
	if ub.Booking.PaidAt != nil {
		return nil
	}
	_, err = s.syncBooking(ctx, bookingID)
	return err
}

// OrderUpdated handles the gateway's webhook for merchantOrderID by asking
// the gateway where the order stands. An order we never opened is ignored.
func (s *PaymentService) OrderUpdated(ctx context.Context, merchantOrderID string) error {
	if s.gateway == nil {
		return ErrPaymentsOff
	}
	o, err := s.store.FindOrder(ctx, merchantOrderID)
	if errors.Is(err, repository.ErrPaymentOrderNotFound) {
		slog.WarnContext(ctx, "payment: webhook for an unknown order", "merchantOrderId", merchantOrderID)
		return nil
	}
	if err != nil {
		return err
	}
	if o.State != domain.PaymentPending {
		return nil
	}
	_, err = s.settle(ctx, o)
	return err
}

// Sweep re-checks every order still pending from the last day, once. It
// returns how many it settled.
func (s *PaymentService) Sweep(ctx context.Context) int {
	if s.gateway == nil {
		return 0
	}
	now := s.now()
	orders, err := s.store.PendingSince(ctx, now.Add(-sweepWindow), now.Add(-sweepMinAge))
	if err != nil {
		slog.WarnContext(ctx, "payment: sweep failed", "error", err)
		return 0
	}
	settled := 0
	for _, o := range orders {
		state, err := s.settle(ctx, o)
		if err != nil {
			slog.WarnContext(ctx, "payment: sweep could not check order",
				"merchantOrderId", o.MerchantOrderID, "error", err)
		} else if state != domain.PaymentPending {
			settled++
		}
	}
	return settled
}

// RunSweeper calls Sweep every sweepEvery until ctx ends.
func (s *PaymentService) RunSweeper(ctx context.Context) {
	if s.gateway == nil {
		return
	}
	t := time.NewTicker(sweepEvery)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if n := s.Sweep(ctx); n > 0 {
				slog.InfoContext(ctx, "payment: sweep settled orders", "count", n)
			}
		}
	}
}

// syncBooking settles bookingID's pending orders and reports whether one of
// them paid it.
func (s *PaymentService) syncBooking(ctx context.Context, bookingID string) (bool, error) {
	orders, err := s.store.PendingForBooking(ctx, bookingID)
	if err != nil {
		return false, err
	}
	paid := false
	for _, o := range orders {
		state, err := s.settle(ctx, o)
		if err != nil {
			return paid, err
		}
		paid = paid || state == domain.PaymentCompleted
	}
	return paid, nil
}

// settle asks the gateway about o and records what it says, returning the
// order's state afterwards.
func (s *PaymentService) settle(ctx context.Context, o domain.PaymentOrder) (domain.PaymentState, error) {
	st, err := s.gateway.OrderStatus(ctx, o.MerchantOrderID)
	if err != nil {
		return domain.PaymentPending, err
	}
	now := s.now()
	switch st.State {
	case domain.PaymentPending:
		return domain.PaymentPending, nil
	case domain.PaymentFailed:
		if err := s.store.FailOrder(ctx, o.MerchantOrderID, st, now); err != nil {
			return domain.PaymentPending, err
		}
		slog.InfoContext(ctx, "payment: order failed", "merchantOrderId", o.MerchantOrderID, "bookingId", o.BookingID)
		return domain.PaymentFailed, nil
	}
	// Completed. The gateway's amount must be what we asked for.
	if st.AmountPaise != o.AmountPaise {
		slog.ErrorContext(ctx, "payment: completed order's amount doesn't match; left pending for a manual check",
			"merchantOrderId", o.MerchantOrderID, "want", o.AmountPaise, "got", st.AmountPaise)
		return domain.PaymentPending, nil
	}
	outcome, b, err := s.store.CompleteOrder(ctx, o, st, s.commission(st.AmountPaise), now)
	if err != nil {
		return domain.PaymentPending, err
	}
	switch outcome {
	case domain.SettledPaidTwice:
		slog.ErrorContext(ctx, "payment: ride paid twice; refund this order by hand",
			"merchantOrderId", o.MerchantOrderID, "bookingId", o.BookingID,
			"transactionId", st.TransactionID, "utr", st.UTR, "amountPaise", st.AmountPaise)
	case domain.SettledNow:
		slog.InfoContext(ctx, "payment: ride paid",
			"bookingId", b.ID, "merchantOrderId", o.MerchantOrderID, "amountPaise", st.AmountPaise,
			"mode", st.PaymentMode, "utr", st.UTR)
		if s.alerts != nil && b.DriverID != "" {
			s.alerts.PaymentReceived(ctx, b)
		}
	}
	return domain.PaymentCompleted, nil
}

// commission is MOJUD's cut of amount, rounded to the nearest paisa.
func (s *PaymentService) commission(amount int64) int64 {
	return (amount*s.commissionBP + 5000) / 10000
}

// newMerchantOrderID names a checkout for bookingID: "MOJUD_", the booking
// id without dashes, and the time in base 36 — at most 63 characters of
// letters, digits and underscores, as the gateway requires.
func newMerchantOrderID(bookingID string, now time.Time) string {
	return "MOJUD_" + strings.ReplaceAll(bookingID, "-", "") + "_" +
		strconv.FormatInt(now.UnixMilli(), 36)
}
