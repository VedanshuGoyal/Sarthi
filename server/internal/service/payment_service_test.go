package service

import (
	"context"
	"errors"
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
	return domain.GatewayOrder{ProviderOrderID: "OMO-" + id, Token: "tok", ExpiresAt: testNow.Add(ttl)}, nil
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
	o.State, o.CreatedAt = domain.PaymentPending, testNow
	s.orders[o.MerchantOrderID] = &o
	s.order = append(s.order, o.MerchantOrderID)
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

func (s *fakePaymentStore) PendingForBooking(_ context.Context, bookingID string) ([]domain.PaymentOrder, error) {
	return s.pending(func(o domain.PaymentOrder) bool { return o.BookingID == bookingID }), nil
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

func (s *fakePaymentStore) CompleteOrder(_ context.Context, o domain.PaymentOrder, st domain.GatewayOrderStatus, commission int64, at time.Time) (domain.SettleOutcome, domain.Booking, error) {
	outcome := domain.SettledAlready
	stored := s.orders[o.MerchantOrderID]
	b := s.bookings[o.BookingID]
	if stored.State == domain.PaymentPending {
		stored.State = domain.PaymentCompleted
		outcome = domain.SettledPaidTwice
		if b.PaidAt == nil {
			b.PaidAt, b.PaidPaise, b.CommissionPaise = &at, st.AmountPaise, commission
			outcome = domain.SettledNow
		}
	}
	return outcome, *b, nil
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
	if c.AmountPaise != 45000 || c.MerchantID != "M1" || c.Environment != "SANDBOX" || c.Token != "tok" {
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
	store := newFakePaymentStore(completedBooking("b1", 20000), completedBooking("b2", 20000))
	gw := &fakeGateway{}
	alerts := &recordingPaymentAlerts{}
	svc := newPayments(store, gw, alerts, 0)
	ctx := context.Background()

	c1, _ := svc.Checkout(ctx, "u1", "b1")
	_, _ = svc.Checkout(ctx, "u1", "b2")
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
