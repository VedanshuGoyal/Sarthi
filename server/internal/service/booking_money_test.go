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
func (a *requestAlerts) RideCancelled(context.Context, domain.Booking, tripPlan) {}

// A customer with a completed ride still to pay is refused before anything
// is read or stored, with the ride to pay named.
func TestBookingService_Record_refusedWhileARideIsUnpaid(t *testing.T) {
	store := &fakeBookingStore{unpaid: "done-1"}
	svc := newTestBookingService(store)

	_, _, err := svc.Record(context.Background(), "u1", TripRoundTrip, roundTripDetails(), "k1")
	if !errors.Is(err, ErrPaymentDue) {
		t.Fatalf("err = %v, want ErrPaymentDue", err)
	}
	due, ok := errors.AsType[*PaymentDueError](err)
	if !ok || due.BookingID != "done-1" {
		t.Errorf("err = %#v, want a PaymentDueError naming done-1", err)
	}
	if store.insertHit {
		t.Error("a booking was stored for a customer who owes a ride")
	}
	// Rides under the gateway's minimum can't be paid, so can't block.
	if store.unpaidMin != minPaymentPaise {
		t.Errorf("unpaid check used minimum %d, want %d", store.unpaidMin, minPaymentPaise)
	}
}

// With no payment gateway the customer can't pay in the app, so an unpaid
// ride doesn't stop them booking again.
func TestBookingService_Record_paymentsOffSkipsTheUnpaidCheck(t *testing.T) {
	store := &fakeBookingStore{unpaid: "done-1"}
	svc := newTestBookingService(store)
	svc.SetPaymentsEnabled(false)

	if _, _, err := svc.Record(context.Background(), "u1", TripRoundTrip, roundTripDetails(), "k1"); err != nil {
		t.Fatalf("Record: %v, want the booking stored", err)
	}
	if !store.insertHit {
		t.Error("the booking was not stored")
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
