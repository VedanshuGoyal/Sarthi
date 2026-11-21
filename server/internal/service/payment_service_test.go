package service

import (
	"context"
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// fakeGateway hands out orders and reports whatever state a test sets.
type fakeGateway struct {
	mu      sync.Mutex
	created []string
	status  map[string]domain.GatewayOrderStatus
}

func (g *fakeGateway) Name() string        { return "phonepe" }
func (g *fakeGateway) MerchantID() string  { return "M1" }
func (g *fakeGateway) Environment() string { return "SANDBOX" }

func (g *fakeGateway) CreateOrder(_ context.Context, id string, amount int64, ttl time.Duration) (domain.GatewayOrder, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.created = append(g.created, id)
	return domain.GatewayOrder{ProviderOrderID: "OMO-" + id, Token: "tok-" + id, ExpiresAt: testNow.Add(ttl)}, nil
}

func (g *fakeGateway) OrderStatus(_ context.Context, id string) (domain.GatewayOrderStatus, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if st, ok := g.status[id]; ok {
		return st, nil
	}
	return domain.GatewayOrderStatus{State: domain.PaymentPending}, nil
}

func (g *fakeGateway) set(id string, st domain.GatewayOrderStatus) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.status == nil {
		g.status = map[string]domain.GatewayOrderStatus{}
	}
	g.status[id] = st
}

// fakePaymentStore keeps orders and bookings in maps, mirroring the
// repository's rules.
type fakePaymentStore struct {
	bookings map[string]*domain.Booking
	orders   map[string]*domain.PaymentOrder
	order    []string
	// insertErrs are returned by the next InsertOrder calls, one each.
	insertErrs []error
}

func newFakePaymentStore(bs ...domain.Booking) *fakePaymentStore {
	s := &fakePaymentStore{bookings: map[string]*domain.Booking{}, orders: map[string]*domain.PaymentOrder{}}
	for i := range bs {
		b := bs[i]
		s.bookings[b.ID] = &b
	}
	return s
}

func (s *fakePaymentStore) FindForUser(_ context.Context, id, userID string) (domain.UserBooking, error) {
	b, ok := s.bookings[id]
	if !ok || b.UserID != userID {
		return domain.UserBooking{}, repository.ErrBookingNotFound
	}
	return domain.UserBooking{Booking: *b}, nil
}

func (s *fakePaymentStore) InsertOrder(_ context.Context, o domain.PaymentOrder) error {
	if len(s.insertErrs) > 0 {
		err := s.insertErrs[0]
		s.insertErrs = s.insertErrs[1:]
		return err
	}
	o.State, o.CreatedAt = domain.PaymentPending, testNow
	s.orders[o.MerchantOrderID] = &o
	s.order = append(s.order, o.MerchantOrderID)
	return nil
}

func (s *fakePaymentStore) ReplaceOrders(_ context.Context, ids []string) error {
	for _, id := range ids {
		if o := s.orders[id]; o != nil && o.State == domain.PaymentPending {
			o.CheckoutToken = ""
		}
	}
	return nil
}

func (s *fakePaymentStore) FindOrder(_ context.Context, id string) (domain.PaymentOrder, error) {
	o, ok := s.orders[id]
	if !ok {
		return domain.PaymentOrder{}, repository.ErrPaymentOrderNotFound
	}
	return *o, nil
}

func (s *fakePaymentStore) pending(keep func(domain.PaymentOrder) bool) []domain.PaymentOrder {
	var out []domain.PaymentOrder
	for _, id := range s.order {
		if o := s.orders[id]; o.State == domain.PaymentPending && keep(*o) {
			out = append(out, *o)
		}
	}
	return out
}

// items is what o pays: its items, or its own booking in full.
func items(o domain.PaymentOrder) []domain.PaymentItem {
	if len(o.Items) > 0 {
		return o.Items
	}
	return []domain.PaymentItem{{BookingID: o.BookingID, AmountPaise: o.AmountPaise}}
}

func (s *fakePaymentStore) PendingForBookings(_ context.Context, ids []string) ([]domain.PaymentOrder, error) {
	return s.pending(func(o domain.PaymentOrder) bool {
		for _, it := range items(o) {
			if slices.Contains(ids, it.BookingID) {
				return true
			}
		}
		return false
	}), nil
}

func (s *fakePaymentStore) OrderItems(_ context.Context, id string) ([]domain.PaymentItem, error) {
	if o := s.orders[id]; o != nil {
		return o.Items, nil
	}
	return nil, nil
}

// UnpaidDues lists u's unpaid completed rides and fees, in id order.
func (s *fakePaymentStore) UnpaidDues(_ context.Context, userID string) ([]domain.Due, error) {
	var out []domain.Due
	for _, b := range s.bookings {
		if b.UserID == userID && b.PaidAt == nil && b.AmountDue() > 0 {
			out = append(out, domain.Due{BookingID: b.ID, AmountPaise: b.AmountDue()})
		}
	}
	slices.SortFunc(out, func(a, b domain.Due) int { return strings.Compare(a.BookingID, b.BookingID) })
	return out, nil
}

func (s *fakePaymentStore) PendingSince(_ context.Context, from, to time.Time) ([]domain.PaymentOrder, error) {
	return s.pending(func(o domain.PaymentOrder) bool {
		return !o.CreatedAt.Before(from) && o.CreatedAt.Before(to)
	}), nil
}

func (s *fakePaymentStore) FailOrder(_ context.Context, id string, _ domain.GatewayOrderStatus, _ time.Time) error {
	if o := s.orders[id]; o != nil && o.State == domain.PaymentPending {
		o.State = domain.PaymentFailed
	}
	return nil
}

func (s *fakePaymentStore) CompleteOrder(_ context.Context, o domain.PaymentOrder, st domain.GatewayOrderStatus, bp int64, at time.Time) (domain.SettleResult, error) {
	res := domain.SettleResult{Outcome: domain.SettledAlready}
	stored := s.orders[o.MerchantOrderID]
	if stored.State != domain.PaymentPending {
		return res, nil
	}
	stored.State = domain.PaymentCompleted
	for _, it := range items(*stored) {
		b := s.bookings[it.BookingID]
		if b.PaidAt != nil {
			res.AlreadyPaid = append(res.AlreadyPaid, b.ID)
			continue
		}
		b.PaidAt, b.PaidPaise, b.CommissionPaise = &at, it.AmountPaise, (it.AmountPaise*bp+5000)/10000
		res.Paid = append(res.Paid, *b)
	}
	res.Outcome = domain.SettledNow
	if len(res.AlreadyPaid) > 0 {
		res.Outcome = domain.SettledPaidTwice
	}
	return res, nil
}

type recordingPaymentAlerts struct{ paid []string }

func (r *recordingPaymentAlerts) PaymentReceived(_ context.Context, b domain.Booking) {
	r.paid = append(r.paid, b.ID)
}

func completedBooking(id string, fare int64) domain.Booking {
	return domain.Booking{ID: id, UserID: "u1", DriverID: "d1", Status: domain.RideStatusCompleted, FarePaise: fare}
}

func newPayments(store *fakePaymentStore, gw *fakeGateway, alerts *recordingPaymentAlerts, bp int64) *PaymentService {
	s := NewPaymentService(gw, store, store, alerts, bp)
	s.now = func() time.Time { return testNow }
	return s
}

func TestCheckout_onlyForCompletedUnpaidRides(t *testing.T) {
	ongoing := completedBooking("b-ongoing", 45000)
	ongoing.Status = domain.RideStatusInProgress
	store := newFakePaymentStore(ongoing, completedBooking("b-done", 45000), completedBooking("b-free", 0))
	svc := newPayments(store, &fakeGateway{}, &recordingPaymentAlerts{}, 0)
	ctx := context.Background()

	if _, err := svc.Checkout(ctx, "u1", "b-ongoing"); !errors.Is(err, ErrNotPayable) {
		t.Errorf("in-progress ride: err = %v, want ErrNotPayable", err)
	}
	if _, err := svc.Checkout(ctx, "u1", "b-free"); !errors.Is(err, ErrNotPayable) {
		t.Errorf("zero fare: err = %v, want ErrNotPayable", err)
	}
	if _, err := svc.Checkout(ctx, "someone-else", "b-done"); !errors.Is(err, repository.ErrBookingNotFound) {
		t.Errorf("another customer's ride: err = %v, want ErrBookingNotFound", err)
	}

	c, err := svc.Checkout(ctx, "u1", "b-done")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	if c.AmountPaise != 45000 || c.MerchantID != "M1" || c.Environment != "SANDBOX" || c.Token != "tok-"+c.MerchantOrderID {
		t.Errorf("checkout = %+v", c)
	}
	if len(c.MerchantOrderID) > 63 || !strings.HasPrefix(c.MerchantOrderID, "MOJUD_") || strings.Contains(c.MerchantOrderID, "-") {
		t.Errorf("merchant order id %q breaks the gateway's rules", c.MerchantOrderID)
	}
}

func TestSync_paysOnceWithCommissionAndTellsTheDriver(t *testing.T) {
	store := newFakePaymentStore(completedBooking("b1", 45000))
	gw := &fakeGateway{}
	alerts := &recordingPaymentAlerts{}
	svc := newPayments(store, gw, alerts, 1500) // 15%
	ctx := context.Background()

	c, err := svc.Checkout(ctx, "u1", "b1")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	// Still pending at the gateway: nothing changes.
	if err := svc.Sync(ctx, "u1", "b1"); err != nil {
		t.Fatalf("Sync: %v", err)
	}
	if store.bookings["b1"].PaidAt != nil {
		t.Fatal("paid while the gateway said pending")
	}

	gw.set(c.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 45000, UTR: "4123"})
	if err := svc.Sync(ctx, "u1", "b1"); err != nil {
		t.Fatalf("Sync: %v", err)
	}
	b := store.bookings["b1"]
	if b.PaidAt == nil || b.PaidPaise != 45000 || b.CommissionPaise != 6750 {
		t.Fatalf("booking after payment = %+v", b)
	}
	if b.PaymentStatus() != domain.RidePaymentPaid {
		t.Errorf("PaymentStatus = %q", b.PaymentStatus())
	}
	if len(alerts.paid) != 1 {
		t.Errorf("driver alerts = %v, want one", alerts.paid)
	}

	// The webhook arriving afterwards changes nothing and alerts no one.
	if err := svc.OrderUpdated(ctx, c.MerchantOrderID); err != nil {
		t.Fatalf("OrderUpdated: %v", err)
	}
	if len(alerts.paid) != 1 {
		t.Errorf("driver alerted again: %v", alerts.paid)
	}
	if _, err := svc.Checkout(ctx, "u1", "b1"); !errors.Is(err, ErrAlreadyPaid) {
		t.Errorf("second checkout: err = %v, want ErrAlreadyPaid", err)
	}
}

func TestCheckout_findsAnEarlierCheckoutThatWentThrough(t *testing.T) {
	store := newFakePaymentStore(completedBooking("b1", 30000))
	gw := &fakeGateway{}
	svc := newPayments(store, gw, &recordingPaymentAlerts{}, 0)
	ctx := context.Background()

	first, err := svc.Checkout(ctx, "u1", "b1")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	gw.set(first.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 30000})
	if _, err := svc.Checkout(ctx, "u1", "b1"); !errors.Is(err, ErrAlreadyPaid) {
		t.Fatalf("checkout after paying: err = %v, want ErrAlreadyPaid", err)
	}
	if len(gw.created) != 1 {
		t.Errorf("orders created = %d, want 1", len(gw.created))
	}
}

// HUMAN REVIEW REQUIRED: payments. The gateway's page won't open again
// for an order the customer left, so a second tap on Pay replaces the open
// order with a new one — unless a payment on it is under way, which could
// still land: then the customer waits instead of paying twice.
func TestCheckout_replacesAnOpenCheckoutUnlessItIsBeingPaid(t *testing.T) {
	store := newFakePaymentStore(completedBooking("b1", 30000))
	gw := &fakeGateway{}
	svc := newPayments(store, gw, &recordingPaymentAlerts{}, 0)
	ctx := context.Background()

	first, err := svc.Checkout(ctx, "u1", "b1")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	svc.now = func() time.Time { return testNow.Add(time.Minute) }
	second, err := svc.Checkout(ctx, "u1", "b1")
	if err != nil {
		t.Fatalf("second Checkout: %v", err)
	}
	if second.MerchantOrderID == first.MerchantOrderID || second.AmountPaise != 30000 || len(gw.created) != 2 {
		t.Fatalf("second tap = %s for %d (orders created %d), want a new order for 30000",
			second.MerchantOrderID, second.AmountPaise, len(gw.created))
	}
	if tok := store.orders[first.MerchantOrderID].CheckoutToken; tok != "" {
		t.Errorf("replaced order kept its token %q", tok)
	}

	// The customer is in their UPI app paying the second one.
	gw.set(second.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentPending, Attempting: true})
	if _, err := svc.Checkout(ctx, "u1", "b1"); !errors.Is(err, ErrPaymentUnderway) {
		t.Fatalf("Checkout while paying: err = %v, want ErrPaymentUnderway", err)
	}
	if len(gw.created) != 2 || store.orders[second.MerchantOrderID].CheckoutToken == "" {
		t.Error("a new order was opened, or the one being paid replaced, while a payment was under way")
	}

	// Long past its expiry and still "under way": the gateway has lost it,
	// and the customer can pay again.
	svc.now = func() time.Time { return second.ExpiresAt.Add(attemptGrace + time.Second) }
	stuck, err := svc.Checkout(ctx, "u1", "b1")
	if err != nil || stuck.MerchantOrderID == second.MerchantOrderID {
		t.Fatalf("Checkout past the grace = %s, %v; want a new order", stuck.MerchantOrderID, err)
	}
	gw.set(stuck.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentPending, Attempting: true})

	// That attempt failed: a fresh order.
	gw.set(stuck.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentFailed})
	svc.now = func() time.Time { return second.ExpiresAt.Add(attemptGrace + time.Minute) }
	next, err := svc.Checkout(ctx, "u1", "b1")
	if err != nil {
		t.Fatalf("Checkout after a failure: %v", err)
	}
	if next.MerchantOrderID == stuck.MerchantOrderID || len(gw.created) != 4 {
		t.Errorf("after the failure got %s (created %d), want a new order", next.MerchantOrderID, len(gw.created))
	}
}

// An order opened before tokens were stored is replaced like any other: the
// customer gets a new one.
func TestCheckout_replacesAnOrderWithoutAToken(t *testing.T) {
	store := newFakePaymentStore(completedBooking("b1", 30000))
	_ = store.InsertOrder(context.Background(), domain.PaymentOrder{
		MerchantOrderID: "MOJUD_old_1", BookingID: "b1", UserID: "u1", AmountPaise: 30000,
		ProviderOrderID: "OMO-old", ExpiresAt: testNow.Add(10 * time.Minute),
	})
	gw := &fakeGateway{}
	c, err := newPayments(store, gw, &recordingPaymentAlerts{}, 0).Checkout(context.Background(), "u1", "b1")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	if c.MerchantOrderID == "MOJUD_old_1" || len(gw.created) != 1 {
		t.Errorf("checkout = %s (created %d), want a new order", c.MerchantOrderID, len(gw.created))
	}
}

func TestSettle_wrongAmountStaysPendingAndFailuresClose(t *testing.T) {
	store := newFakePaymentStore(completedBooking("b1", 45000))
	gw := &fakeGateway{}
	svc := newPayments(store, gw, &recordingPaymentAlerts{}, 0)
	ctx := context.Background()

	c, _ := svc.Checkout(ctx, "u1", "b1")
	gw.set(c.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 100})
	if err := svc.OrderUpdated(ctx, c.MerchantOrderID); err != nil {
		t.Fatalf("OrderUpdated: %v", err)
	}
	if store.bookings["b1"].PaidAt != nil || store.orders[c.MerchantOrderID].State != domain.PaymentPending {
		t.Fatal("a completed order for the wrong amount paid the ride")
	}

	gw.set(c.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentFailed})
	if err := svc.OrderUpdated(ctx, c.MerchantOrderID); err != nil {
		t.Fatalf("OrderUpdated: %v", err)
	}
	if store.orders[c.MerchantOrderID].State != domain.PaymentFailed {
		t.Errorf("order state = %q, want failed", store.orders[c.MerchantOrderID].State)
	}
	if err := svc.OrderUpdated(ctx, "MOJUD_unknown_1"); err != nil {
		t.Errorf("unknown order: %v", err)
	}
}

func TestSweep_settlesOrdersTheAppNeverCameBackFor(t *testing.T) {
	other := completedBooking("b2", 20000)
	other.UserID = "u2" // another customer's, so not carried into b1's payment
	store := newFakePaymentStore(completedBooking("b1", 20000), other)
	gw := &fakeGateway{}
	alerts := &recordingPaymentAlerts{}
	svc := newPayments(store, gw, alerts, 0)
	ctx := context.Background()

	c1, _ := svc.Checkout(ctx, "u1", "b1")
	_, _ = svc.Checkout(ctx, "u2", "b2")
	gw.set(c1.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 20000})

	// Orders younger than sweepMinAge are left alone.
	if n := svc.Sweep(ctx); n != 0 {
		t.Fatalf("swept %d fresh orders", n)
	}
	svc.now = func() time.Time { return testNow.Add(5 * time.Minute) }
	if n := svc.Sweep(ctx); n != 1 {
		t.Errorf("settled = %d, want 1", n)
	}
	if store.bookings["b1"].PaidAt == nil || store.bookings["b2"].PaidAt != nil {
		t.Errorf("paid: b1=%v b2=%v", store.bookings["b1"].PaidAt, store.bookings["b2"].PaidAt)
	}
}

// HUMAN REVIEW REQUIRED: payments. Paying one ride collects everything
// else the customer owes in the same order; when it lands, each booking is
// paid its own part with its own commission, and each driver hears of it.
func TestCheckout_carriesOtherDues(t *testing.T) {
	fee := domain.Booking{ID: "a-fee", UserID: "u1", DriverID: "d2", Status: domain.RideStatusCancelled,
		CancellationFeePaise: domain.CancellationFeePaise}
	store := newFakePaymentStore(completedBooking("b-ride", 24000), fee, completedBooking("c-old", 13900))
	gw := &fakeGateway{}
	alerts := &recordingPaymentAlerts{}
	svc := newPayments(store, gw, alerts, 1300)
	ctx := context.Background()

	c, err := svc.Checkout(ctx, "u1", "b-ride")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	if c.AmountPaise != 24000+5000+13900 {
		t.Fatalf("checkout amount = %d, want the ride plus what's carried (42900)", c.AmountPaise)
	}
	// Tapping Pay on a carried booking replaces that order with one for the
	// same total.
	again, err := svc.Checkout(ctx, "u1", "a-fee")
	if err != nil || again.MerchantOrderID == c.MerchantOrderID || again.AmountPaise != 42900 {
		t.Fatalf("Checkout(carried) = %s for %d, %v; want a new order for 42900", again.MerchantOrderID, again.AmountPaise, err)
	}

	gw.set(again.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 42900})
	if err := svc.Sync(ctx, "u1", "b-ride"); err != nil {
		t.Fatalf("Sync: %v", err)
	}
	for id, want := range map[string][2]int64{"b-ride": {24000, 3120}, "a-fee": {5000, 650}, "c-old": {13900, 1807}} {
		b := store.bookings[id]
		if b.PaidAt == nil || b.PaidPaise != want[0] || b.CommissionPaise != want[1] {
			t.Errorf("%s: paid %v %d commission %d, want %d / %d", id, b.PaidAt != nil, b.PaidPaise, b.CommissionPaise, want[0], want[1])
		}
	}
	if len(alerts.paid) != 3 {
		t.Errorf("drivers told = %v, want all three bookings", alerts.paid)
	}
	if _, err := svc.Checkout(ctx, "u1", "c-old"); !errors.Is(err, ErrAlreadyPaid) {
		t.Errorf("paying a carried booking again: err = %v, want ErrAlreadyPaid", err)
	}
}

func TestCommissionRounding(t *testing.T) {
	svc := &PaymentService{commissionBP: 1250} // 12.5%
	for _, tc := range []struct{ amount, want int64 }{
		{45000, 5625}, {101, 13}, {100, 13}, {0, 0},
	} {
		if got := svc.commission(tc.amount); got != tc.want {
			t.Errorf("commission(%d) = %d, want %d", tc.amount, got, tc.want)
		}
	}
}

func TestPaymentsOff(t *testing.T) {
	svc := NewPaymentService(nil, nil, nil, nil, 0)
	if _, err := svc.Checkout(context.Background(), "u1", "b1"); !errors.Is(err, ErrPaymentsOff) {
		t.Errorf("err = %v, want ErrPaymentsOff", err)
	}
	if svc.Sweep(context.Background()) != 0 {
		t.Error("swept with payments off")
	}
}

// HUMAN REVIEW REQUIRED: payments. A booking is never in two orders that
// can still be opened: a new due joins a new order that replaces the open
// one. If the replaced order is paid after all, each ride is still paid once
// and the rest is left for a refund (paid twice).
func TestCheckout_neverTwoOpenOrdersForABooking(t *testing.T) {
	store := newFakePaymentStore(completedBooking("a-ride", 24000))
	gw := &fakeGateway{}
	svc := newPayments(store, gw, &recordingPaymentAlerts{}, 1300)
	ctx := context.Background()

	first, err := svc.Checkout(ctx, "u1", "a-ride")
	if err != nil || first.AmountPaise != 24000 {
		t.Fatalf("Checkout(a) = %d, %v; want 24000", first.AmountPaise, err)
	}
	// Ride b completes while a's checkout is still open.
	b := completedBooking("b-ride", 13900)
	store.bookings[b.ID] = &b

	second, err := svc.Checkout(ctx, "u1", "b-ride")
	if err != nil {
		t.Fatalf("Checkout(b): %v", err)
	}
	if second.MerchantOrderID == first.MerchantOrderID || second.AmountPaise != 24000+13900 {
		t.Errorf("Checkout(b) = %s for %d; want a new order for both rides (37900)", second.MerchantOrderID, second.AmountPaise)
	}
	for _, id := range []string{"a-ride", "b-ride"} {
		open := 0
		for _, o := range store.orders {
			if o.State == domain.PaymentPending && o.CheckoutToken != "" && slices.ContainsFunc(items(*o),
				func(it domain.PaymentItem) bool { return it.BookingID == id }) {
				open++
			}
		}
		if open != 1 {
			t.Errorf("%s is in %d orders that can be opened, want 1", id, open)
		}
	}

	// The replaced order is paid after all, and so is the new one: each
	// ride is paid once.
	gw.set(first.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 24000})
	gw.set(second.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 37900})
	if err := svc.Sync(ctx, "u1", "a-ride"); err != nil {
		t.Fatalf("Sync(a): %v", err)
	}
	if err := svc.Sync(ctx, "u1", "b-ride"); err != nil {
		t.Fatalf("Sync(b): %v", err)
	}
	for id, want := range map[string]int64{"a-ride": 24000, "b-ride": 13900} {
		if got := store.bookings[id]; got.PaidAt == nil || got.PaidPaise != want {
			t.Errorf("%s: paid %v %d, want %d", id, got.PaidAt != nil, got.PaidPaise, want)
		}
	}
}

// HUMAN REVIEW REQUIRED: payments. A state the gateway client doesn't know
// is never taken as money received.
func TestSettle_unknownStateStaysPending(t *testing.T) {
	store := newFakePaymentStore(completedBooking("a-ride", 24000))
	gw := &fakeGateway{}
	svc := newPayments(store, gw, &recordingPaymentAlerts{}, 1300)
	ctx := context.Background()
	c, err := svc.Checkout(ctx, "u1", "a-ride")
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	gw.set(c.MerchantOrderID, domain.GatewayOrderStatus{State: domain.PaymentState("refunded"), AmountPaise: 24000})
	if err := svc.Sync(ctx, "u1", "a-ride"); err != nil {
		t.Fatalf("Sync: %v", err)
	}
	if b := store.bookings["a-ride"]; b.PaidAt != nil {
		t.Errorf("booking paid on an unknown gateway state")
	}
}

// HUMAN REVIEW REQUIRED: payments. When the database refuses a new order
// because another process opened one for the same dues, Checkout looks again
// (and replaces that one, as nobody is paying it).
func TestCheckout_retriesWhenAnotherProcessOpenedAnOrder(t *testing.T) {
	store := newFakePaymentStore(completedBooking("a-ride", 24000))
	store.insertErrs = []error{repository.ErrOrderOpen}
	gw := &fakeGateway{}
	svc := newPayments(store, gw, &recordingPaymentAlerts{}, 1300)
	c, err := svc.Checkout(context.Background(), "u1", "a-ride")
	if err != nil || c.AmountPaise != 24000 {
		t.Fatalf("Checkout = %d, %v; want 24000 after one retry", c.AmountPaise, err)
	}
	if len(gw.created) != 2 {
		t.Errorf("gateway orders = %d, want 2 (the refused one and the retry)", len(gw.created))
	}
}
