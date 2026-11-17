package service

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// requestAlerts counts the "new ride request" fan-outs Record starts.
type requestAlerts struct{ requested []string }

func (a *requestAlerts) RideRequested(_ context.Context, b domain.Booking, _ tripPlan) {
	a.requested = append(a.requested, b.ID)
}
func (a *requestAlerts) RideCancelled(context.Context, domain.Booking, tripPlan)  {}
func (a *requestAlerts) RideEndedEarly(context.Context, domain.Booking, tripPlan) {}

// HUMAN REVIEW REQUIRED: payments. A customer who owes for a ride or fee
// can still book; what they owe shows as carried on the new booking and on
// the one still due, to be collected with the next payment.
func TestBookingService_unpaidRideIsCarriedNotBlocking(t *testing.T) {
	due := customerRide("done-1", domain.RideStatusCompleted, "d1")
	due.Booking.FarePaise = 44000
	fee := customerRide("fee-1", domain.RideStatusCancelled, "d1")
	fee.Booking.CancellationFeePaise = domain.CancellationFeePaise
	store := &fakeBookingStore{
		listed: []domain.UserBooking{due, fee, customerRide("next", domain.RideStatusAccepted, "d2"),
			customerRide("gone", domain.RideStatusCancelled, "")},
		dues: []domain.Due{{BookingID: "done-1", AmountPaise: 44000}, {BookingID: "fee-1", AmountPaise: 5000}},
	}
	svc := newTestBookingService(store)
	ctx := context.Background()

	if _, _, err := svc.Record(ctx, "u1", TripRoundTrip, roundTripDetails(), "k1"); err != nil || !store.insertHit {
		t.Fatalf("Record: %v (stored %v), want the booking stored", err, store.insertHit)
	}
	got, err := svc.ListMine(ctx, "u1")
	if err != nil {
		t.Fatal(err)
	}
	carried := map[string]int64{}
	for _, b := range got {
		carried[b.ID] = b.CarriedPaise
	}
	// Each due booking carries the other; the upcoming ride carries both;
	// a free cancellation carries nothing.
	want := map[string]int64{"done-1": 5000, "fee-1": 44000, "next": 49000, "gone": 0}
	for id, w := range want {
		if carried[id] != w {
			t.Errorf("%s: carriedPaise = %d, want %d", id, carried[id], w)
		}
	}
	if one, _ := svc.mine(ctx, "u1", "next"); one.CarriedPaise != 49000 {
		t.Errorf("one booking: carriedPaise = %d, want 49000", one.CarriedPaise)
	}

	// Payments off: nothing can be paid, so nothing is carried.
	svc.SetPaymentsEnabled(false)
	if one, _ := svc.mine(ctx, "u1", "next"); one.CarriedPaise != 0 {
		t.Errorf("payments off: carriedPaise = %d, want 0", one.CarriedPaise)
	}
}

// Record hands the store the app's key and the 10-minute window, so a retry
// finds the booking the first try made.
func TestBookingService_Record_passesTheRepeatGuards(t *testing.T) {
	store := &fakeBookingStore{}
	svc := newTestBookingService(store)

	if _, dup, err := svc.Record(context.Background(), "u1", TripRoundTrip, roundTripDetails(), "  key-1 "); err != nil || dup {
		t.Fatalf("Record: duplicate %v, err %v", dup, err)
	}
	if store.params.IdempotencyKey != "key-1" {
		t.Errorf("key = %q, want key-1 (trimmed)", store.params.IdempotencyKey)
	}
	if want := bookingTestNow.Add(-duplicateWindow); !store.params.DuplicateSince.Equal(want) {
		t.Errorf("duplicate window from %v, want %v", store.params.DuplicateSince, want)
	}
}

// A repeat answers with the first booking and alerts no driver a second
// time.
func TestBookingService_Record_repeatReturnsTheFirstBooking(t *testing.T) {
	first := domain.Booking{ID: "bk-first", UserID: "u1", TripType: TripRoundTrip}
	store := &fakeBookingStore{repeat: &first}
	alerts := &requestAlerts{}
	svc := NewBookingService(store, alerts, nil, nil)
	svc.now = func() time.Time { return bookingTestNow }

	got, dup, err := svc.Record(context.Background(), "u1", TripRoundTrip, roundTripDetails(), "")
	if err != nil {
		t.Fatalf("Record: %v", err)
	}
	if !dup || got.ID != "bk-first" {
		t.Errorf("got %q (duplicate %v), want bk-first as a duplicate", got.ID, dup)
	}
	if len(alerts.requested) != 0 {
		t.Errorf("drivers alerted again for a repeat: %v", alerts.requested)
	}

	// A new booking does alert.
	store.repeat = nil
	if _, dup, err := svc.Record(context.Background(), "u1", TripRoundTrip, roundTripDetails(), ""); err != nil || dup {
		t.Fatalf("Record: duplicate %v, err %v", dup, err)
	}
	if len(alerts.requested) != 1 {
		t.Errorf("alerts = %v, want one for the new booking", alerts.requested)
	}
}

func TestBookingService_Record_refusesAnOverlongKey(t *testing.T) {
	store := &fakeBookingStore{}
	_, _, err := newTestBookingService(store).Record(context.Background(), "u1", TripRoundTrip,
		roundTripDetails(), strings.Repeat("k", maxIdempotencyKey+1))
	if !errors.Is(err, ErrInvalidBooking) || store.insertHit {
		t.Errorf("err = %v (stored %v), want ErrInvalidBooking and nothing stored", err, store.insertHit)
	}
}

// The customer's receipt: how a paid ride was paid, and a round trip's fare
// split into tariff and night surcharge when they add up to it.
func TestBookingService_ListMine_receipt(t *testing.T) {
	paidAt := time.Date(2026, 10, 24, 14, 0, 0, 0, time.UTC)
	night := roundTripDetails()
	night["scheduledAt"] = "2026-10-24T21:00:00.000" // 9pm IST for 3h: 2 night hours
	night["hours"] = 3.0
	night["fare"] = 340.0 + 50 + 24*2 // sedan, 3h: 340 + night 98
	nightAt := time.Date(2026, 10, 24, 15, 30, 0, 0, time.UTC)
	completed := time.Date(2026, 10, 24, 12, 0, 0, 0, time.UTC)
	store := &fakeBookingStore{listed: []domain.UserBooking{
		{
			Booking: domain.Booking{
				ID: "paid", UserID: "u1", TripType: TripRoundTrip, Details: night, ScheduledAt: &nightAt,
				Status: domain.RideStatusCompleted, CompletedAt: &completed, FarePaise: 43800,
				PaidAt: &paidAt, PaidPaise: 43800, CommissionPaise: 5694,
			},
			Payment: &domain.BookingPayment{Mode: "UPI_INTENT", UTR: "412345678901", MerchantOrderID: "MOJUD_x", PaidAt: paidAt},
		},
		{Booking: domain.Booking{
			ID: "due", UserID: "u1", TripType: TripRoundTrip, Details: roundTripDetails(),
			Status: domain.RideStatusCompleted, CompletedAt: &completed, FarePaise: 44000,
		}},
		{Booking: domain.Booking{
			// Booked at an older tariff: the lines wouldn't add up, so none.
			ID: "old-tariff", UserID: "u1", TripType: TripRoundTrip, Details: roundTripDetails(),
			Status: domain.RideStatusCompleted, CompletedAt: &completed, FarePaise: 39900,
		}},
	}}
	got, err := newTestBookingService(store).ListMine(context.Background(), "u1")
	if err != nil {
		t.Fatalf("ListMine: %v", err)
	}
	byID := map[string]domain.CustomerBooking{}
	for _, b := range got {
		byID[b.ID] = b
	}

	paid := byID["paid"]
	if paid.Payment == nil || paid.Payment.Mode != "UPI_INTENT" || paid.Payment.UTR != "412345678901" {
		t.Errorf("paid ride's payment = %+v", paid.Payment)
	}
	if fb := paid.FareBreakdown; fb == nil || fb.BasePaise != 34000 || fb.NightPaise != 9800 {
		t.Errorf("paid ride's breakdown = %+v, want 34000 + 9800", fb)
	}
	due := byID["due"]
	if due.Payment != nil {
		t.Errorf("an unpaid ride has a payment block: %+v", due.Payment)
	}
	if fb := due.FareBreakdown; fb == nil || fb.BasePaise != 44000 || fb.NightPaise != 0 {
		t.Errorf("day ride's breakdown = %+v, want 44000 + 0", fb)
	}
	if fb := byID["old-tariff"].FareBreakdown; fb != nil {
		t.Errorf("a fare the tariff no longer explains got a breakdown: %+v", fb)
	}
}
