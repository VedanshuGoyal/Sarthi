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

// ErrNotPayable is returned when a customer tries to pay for a booking
// that owes nothing: not completed, or cancelled free.
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

	// checkoutReuseMargin is how long an open checkout must still have to
	// run to be handed out again rather than replaced: time to finish a UPI
	// payment (my estimate).
	checkoutReuseMargin = 2 * time.Minute
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
	OrderItems(ctx context.Context, merchantOrderID string) ([]domain.PaymentItem, error)
	PendingForBookings(ctx context.Context, bookingIDs []string) ([]domain.PaymentOrder, error)
	PendingSince(ctx context.Context, from, to time.Time) ([]domain.PaymentOrder, error)
	FailOrder(ctx context.Context, merchantOrderID string, st domain.GatewayOrderStatus, at time.Time) error
	CompleteOrder(ctx context.Context, o domain.PaymentOrder, st domain.GatewayOrderStatus, commissionBP int64, at time.Time) (domain.SettleResult, error)
}

// CustomerBookingFinder reads one of a customer's bookings and what they
// still owe for (repository.BookingRepository).
type CustomerBookingFinder interface {
	FindForUser(ctx context.Context, id, userID string) (domain.UserBooking, error)
	UnpaidDues(ctx context.Context, userID string) ([]domain.Due, error)
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

// Checkout opens a UPI checkout for userID's completed booking — or the fee
// of one cancelled at the pickup — and returns what the app hands the
// gateway's SDK. Everything else the customer still owes for (an unpaid
// ride or fee) is carried into the same payment: the order pays each of
// those bookings its own part.
//
// Checkouts from earlier taps are found first: one that went through means
// paying again is refused with [ErrAlreadyPaid] (or what is left is totalled again);
// one still open at the gateway for exactly the same bookings (a collect
// request waiting on the customer's UPI app, say) is handed out again
// instead of opening a second payable order.
func (s *PaymentService) Checkout(ctx context.Context, userID, bookingID string) (domain.PaymentCheckout, error) {
	if s.gateway == nil {
		return domain.PaymentCheckout{}, ErrPaymentsOff
	}
	ub, err := s.bookings.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return domain.PaymentCheckout{}, err
	}
	b := ub.Booking
	if b.PaymentStatus() == "" {
		return domain.PaymentCheckout{}, ErrNotPayable
	}
	if b.PaidAt != nil {
		return domain.PaymentCheckout{}, ErrAlreadyPaid
	}
	dues, err := s.bookings.UnpaidDues(ctx, userID)
	if err != nil {
		return domain.PaymentCheckout{}, err
	}
	// A checkout from an earlier tap may have gone through meanwhile.
	paid, open, err := s.syncOrders(ctx, dueIDs(b.ID, dues))
	if err != nil {
		return domain.PaymentCheckout{}, err
	}
	if paid {
		if ub, err = s.bookings.FindForUser(ctx, bookingID, userID); err != nil {
			return domain.PaymentCheckout{}, err
		}
		if b = ub.Booking; b.PaidAt != nil {
			return domain.PaymentCheckout{}, ErrAlreadyPaid
		}
		if dues, err = s.bookings.UnpaidDues(ctx, userID); err != nil {
			return domain.PaymentCheckout{}, err
		}
	}
	items := checkoutItems(b, dues)
	var amount int64
	for _, it := range items {
		amount += it.AmountPaise
	}
	if b.AmountDue() <= 0 || amount < minPaymentPaise {
		return domain.PaymentCheckout{}, ErrNotPayable
	}

	now := s.now()
	if o, ok := reusableCheckout(open, items, now); ok {
		slog.InfoContext(ctx, "payment: checkout reopened",
			"bookingId", b.ID, "userId", userID, "merchantOrderId", o.MerchantOrderID, "amountPaise", amount)
		return s.checkoutFor(o), nil
	}
	merchantOrderID := newMerchantOrderID(b.ID, now)
	order, err := s.gateway.CreateOrder(ctx, merchantOrderID, amount, orderLifetime)
	if err != nil {
		return domain.PaymentCheckout{}, err
	}
	o := domain.PaymentOrder{
		MerchantOrderID: merchantOrderID,
		BookingID:       b.ID,
		UserID:          userID,
		AmountPaise:     amount,
		ProviderOrderID: order.ProviderOrderID,
		CheckoutToken:   order.Token,
		ExpiresAt:       order.ExpiresAt,
		Items:           items,
	}
	if err := s.store.InsertOrder(ctx, o); err != nil {
		return domain.PaymentCheckout{}, err
	}
	slog.InfoContext(ctx, "payment: checkout opened",
		"bookingId", b.ID, "userId", userID, "merchantOrderId", merchantOrderID, "amountPaise", amount,
		"carriedBookings", len(items)-1)
	return s.checkoutFor(o), nil
}

// dueIDs is bookingID and every booking in dues, once each.
func dueIDs(bookingID string, dues []domain.Due) []string {
	ids := []string{bookingID}
	for _, d := range dues {
		if d.BookingID != bookingID {
			ids = append(ids, d.BookingID)
		}
	}
	return ids
}

// checkoutItems is what a payment for b collects: b's own amount first,
// then everything else in dues, oldest first.
func checkoutItems(b domain.Booking, dues []domain.Due) []domain.PaymentItem {
	items := []domain.PaymentItem{{BookingID: b.ID, AmountPaise: b.AmountDue()}}
	for _, d := range dues {
		if d.BookingID != b.ID && d.AmountPaise > 0 {
			items = append(items, domain.PaymentItem{BookingID: d.BookingID, AmountPaise: d.AmountPaise})
		}
	}
	return items
}

// checkoutFor is what the app needs to open order o.
func (s *PaymentService) checkoutFor(o domain.PaymentOrder) domain.PaymentCheckout {
	return domain.PaymentCheckout{
		Provider:        s.gateway.Name(),
		Environment:     s.gateway.Environment(),
		MerchantID:      s.gateway.MerchantID(),
		OrderID:         o.ProviderOrderID,
		Token:           o.CheckoutToken,
		MerchantOrderID: o.MerchantOrderID,
		AmountPaise:     o.AmountPaise,
		ExpiresAt:       o.ExpiresAt,
	}
}

// reusableCheckout picks, from orders the gateway says are still open, the
// one to hand out again: paying exactly items, with its token on file and
// at least checkoutReuseMargin to run. The latest-expiring wins.
func reusableCheckout(open []domain.PaymentOrder, items []domain.PaymentItem, now time.Time) (domain.PaymentOrder, bool) {
	var best domain.PaymentOrder
	found := false
	for _, o := range open {
		if !sameItems(o.Items, items) || o.CheckoutToken == "" || o.ExpiresAt.Before(now.Add(checkoutReuseMargin)) {
			continue
		}
		if !found || o.ExpiresAt.After(best.ExpiresAt) {
			best, found = o, true
		}
	}
	return best, found
}

// sameItems reports whether a and b pay the same bookings the same amounts,
// in any order.
func sameItems(a, b []domain.PaymentItem) bool {
	if len(a) != len(b) {
		return false
	}
	want := make(map[string]int64, len(b))
	for _, it := range b {
		want[it.BookingID] = it.AmountPaise
	}
	for _, it := range a {
		if amount, ok := want[it.BookingID]; !ok || amount != it.AmountPaise {
			return false
		}
	}
	return true
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
	_, _, err = s.syncOrders(ctx, []string{bookingID})
	return err
}

// SyncBooking re-checks bookingID's pending checkouts with the gateway, for
// the back office before it settles the ride by hand: an order the
// customer paid meanwhile is recorded, one that lapsed is failed. Nothing
// to do with payments off.
func (s *PaymentService) SyncBooking(ctx context.Context, bookingID string) error {
	if s.gateway == nil {
		return nil
	}
	_, _, err := s.syncOrders(ctx, []string{bookingID})
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
	_, _, err = s.settle(ctx, o)
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
		state, _, err := s.settle(ctx, o)
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

// syncOrders settles the pending orders that pay any of bookingIDs and
// reports whether one of them completed, and which are still open at the
// gateway — with their items, for reuse.
func (s *PaymentService) syncOrders(ctx context.Context, bookingIDs []string) (bool, []domain.PaymentOrder, error) {
	orders, err := s.store.PendingForBookings(ctx, bookingIDs)
	if err != nil {
		return false, nil, err
	}
	paid := false
	var open []domain.PaymentOrder
	for _, o := range orders {
		state, stillOpen, err := s.settle(ctx, o)
		if err != nil {
			return paid, nil, err
		}
		paid = paid || state == domain.PaymentCompleted
		if stillOpen {
			if o.Items, err = s.store.OrderItems(ctx, o.MerchantOrderID); err != nil {
				return paid, nil, err
			}
			if len(o.Items) == 0 {
				o.Items = []domain.PaymentItem{{BookingID: o.BookingID, AmountPaise: o.AmountPaise}}
			}
			open = append(open, o)
		}
	}
	return paid, open, nil
}

// settle asks the gateway about o and records what it says, returning the
// order's state afterwards and whether the gateway still has it open for
// payment.
func (s *PaymentService) settle(ctx context.Context, o domain.PaymentOrder) (domain.PaymentState, bool, error) {
	st, err := s.gateway.OrderStatus(ctx, o.MerchantOrderID)
	if err != nil {
		return domain.PaymentPending, false, err
	}
	now := s.now()
	switch st.State {
	case domain.PaymentPending:
		return domain.PaymentPending, true, nil
	case domain.PaymentFailed:
		if err := s.store.FailOrder(ctx, o.MerchantOrderID, st, now); err != nil {
			return domain.PaymentPending, false, err
		}
		slog.InfoContext(ctx, "payment: order failed", "merchantOrderId", o.MerchantOrderID, "bookingId", o.BookingID)
		return domain.PaymentFailed, false, nil
	}
	// Completed. The gateway's amount must be what we asked for.
	if st.AmountPaise != o.AmountPaise {
		slog.ErrorContext(ctx, "payment: completed order's amount doesn't match; left pending for a manual check",
			"merchantOrderId", o.MerchantOrderID, "want", o.AmountPaise, "got", st.AmountPaise)
		return domain.PaymentPending, false, nil
	}
	res, err := s.store.CompleteOrder(ctx, o, st, s.commissionBP, now)
	if err != nil {
		return domain.PaymentPending, false, err
	}
	if res.Outcome == domain.SettledPaidTwice {
		slog.ErrorContext(ctx, "payment: ride paid twice; refund this order's part for them by hand",
			"merchantOrderId", o.MerchantOrderID, "bookingId", o.BookingID, "alreadyPaid", res.AlreadyPaid,
			"transactionId", st.TransactionID, "utr", st.UTR, "amountPaise", st.AmountPaise)
	}
	for _, b := range res.Paid {
		slog.InfoContext(ctx, "payment: ride paid",
			"bookingId", b.ID, "merchantOrderId", o.MerchantOrderID, "amountPaise", b.PaidPaise,
			"orderAmountPaise", st.AmountPaise, "mode", st.PaymentMode, "utr", st.UTR)
		if s.alerts != nil && b.DriverID != "" {
			s.alerts.PaymentReceived(ctx, b)
		}
	}
	return domain.PaymentCompleted, false, nil
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
