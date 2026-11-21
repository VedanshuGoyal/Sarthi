package service

import (
	"context"
	"errors"
	"fmt"
	"hash/fnv"
	"log/slog"
	"strconv"
	"strings"
	"sync"
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

// ErrPaymentUnderway is returned when a payment on an earlier checkout is
// still going through at the gateway: a new order now could take the money
// twice. It lands, or fails, within minutes.
var ErrPaymentUnderway = errors.New("your last payment is still going through. Check your UPI app, or try again in a few minutes")

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

	// attemptGrace is how long past its expiry an order with a payment
	// still under way holds up a new one. After that the gateway is taken
	// to have lost it, and a late landing shows as paid twice.
	attemptGrace = 5 * time.Minute
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
	ReplaceOrders(ctx context.Context, merchantOrderIDs []string) error
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
	// checkoutLocks serialise Checkout per customer (striped by user id), so
	// two taps or two devices can't each find no open order and each open
	// one for the same dues.
	checkoutLocks [64]sync.Mutex
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
// paying again is refused with [ErrAlreadyPaid] (or what is left is totalled
// again); one with a payment under way at the gateway (the customer in their
// UPI app) means [ErrPaymentUnderway]. Any other still open is replaced by
// the new order: the gateway's page won't open again for an order the
// customer has left (seen on a phone, 21 Nov 2026).
func (s *PaymentService) Checkout(ctx context.Context, userID, bookingID string) (domain.PaymentCheckout, error) {
	if s.gateway == nil {
		return domain.PaymentCheckout{}, ErrPaymentsOff
	}
	defer s.lockCustomer(userID)()
	c, err := s.checkout(ctx, userID, bookingID)
	if errors.Is(err, repository.ErrOrderOpen) {
		// Another server process opened an order for these dues meanwhile:
		// look again (it is replaced unless someone is paying it).
		c, err = s.checkout(ctx, userID, bookingID)
	}
	return c, err
}

// checkout is one attempt at Checkout, under the customer's lock.
func (s *PaymentService) checkout(ctx context.Context, userID, bookingID string) (domain.PaymentCheckout, error) {
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
	if b.AmountDue() <= 0 {
		return domain.PaymentCheckout{}, ErrNotPayable
	}
	// Earlier orders still open for these dues: wait for one being paid;
	// replace the rest. A replaced order paid after all (from a page still
	// open on another phone) shows in the paid-twice list for a refund.
	now := s.now()
	var replaced []string
	for _, o := range open {
		switch {
		case o.Attempting && now.Before(o.ExpiresAt.Add(attemptGrace)):
			slog.InfoContext(ctx, "payment: checkout refused, a payment is under way",
				"bookingId", b.ID, "userId", userID, "merchantOrderId", o.MerchantOrderID)
			return domain.PaymentCheckout{}, ErrPaymentUnderway
		case o.Attempting:
			slog.ErrorContext(ctx, "payment: replacing an order whose payment never finished; if it lands, it is paid twice",
				"bookingId", b.ID, "userId", userID, "merchantOrderId", o.MerchantOrderID, "expiresAt", o.ExpiresAt)
		}
		replaced = append(replaced, o.MerchantOrderID)
	}
	if len(replaced) > 0 {
		if err := s.store.ReplaceOrders(ctx, replaced); err != nil {
			return domain.PaymentCheckout{}, err
		}
	}
	items := checkoutItems(b, dues)
	var amount int64
	for _, it := range items {
		amount += it.AmountPaise
	}
	if amount < minPaymentPaise {
		return domain.PaymentCheckout{}, ErrNotPayable
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
		"carriedBookings", len(items)-1, "replaced", replaced)
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

// lockCustomer takes userID's checkout lock and returns its unlock.
func (s *PaymentService) lockCustomer(userID string) func() {
	h := fnv.New32a()
	_, _ = h.Write([]byte(userID))
	m := &s.checkoutLocks[h.Sum32()%uint32(len(s.checkoutLocks))]
	m.Lock()
	return m.Unlock
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
// gateway — with their items, and whether a payment on each is under way.
func (s *PaymentService) syncOrders(ctx context.Context, bookingIDs []string) (bool, []domain.PaymentOrder, error) {
	orders, err := s.store.PendingForBookings(ctx, bookingIDs)
	if err != nil {
		return false, nil, err
	}
	paid := false
	var open []domain.PaymentOrder
	for _, o := range orders {
		state, still, err := s.settle(ctx, o)
		if err != nil {
			return paid, nil, err
		}
		paid = paid || state == domain.PaymentCompleted
		if still != notOpen {
			o.Attempting = still == openPaying
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

// openness is whether the gateway still has an order open for payment, and
// if so whether a payment on it is under way.
type openness int

const (
	notOpen openness = iota
	openIdle
	openPaying
)

// settle asks the gateway about o and records what it says, returning the
// order's state afterwards and whether the gateway still has it open.
func (s *PaymentService) settle(ctx context.Context, o domain.PaymentOrder) (domain.PaymentState, openness, error) {
	st, err := s.gateway.OrderStatus(ctx, o.MerchantOrderID)
	if err != nil {
		return domain.PaymentPending, notOpen, err
	}
	now := s.now()
	switch st.State {
	case domain.PaymentPending:
		if st.Attempting {
			return domain.PaymentPending, openPaying, nil
		}
		return domain.PaymentPending, openIdle, nil
	case domain.PaymentFailed:
		if err := s.store.FailOrder(ctx, o.MerchantOrderID, st, now); err != nil {
			return domain.PaymentPending, notOpen, err
		}
		slog.InfoContext(ctx, "payment: order failed", "merchantOrderId", o.MerchantOrderID, "bookingId", o.BookingID)
		return domain.PaymentFailed, notOpen, nil
	case domain.PaymentCompleted:
	default:
		// Never treat a state we don't know as money received.
		slog.ErrorContext(ctx, "payment: gateway sent an unknown order state; left pending",
			"merchantOrderId", o.MerchantOrderID, "state", st.State)
		return domain.PaymentPending, notOpen, nil
	}
	// Completed. The gateway's amount must be what we asked for.
	if st.AmountPaise != o.AmountPaise {
		slog.ErrorContext(ctx, "payment: completed order's amount doesn't match; left pending for a manual check",
			"merchantOrderId", o.MerchantOrderID, "want", o.AmountPaise, "got", st.AmountPaise)
		return domain.PaymentPending, notOpen, nil
	}
	res, err := s.store.CompleteOrder(ctx, o, st, s.commissionBP, now)
	if err != nil {
		return domain.PaymentPending, notOpen, err
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
	return domain.PaymentCompleted, notOpen, nil
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
