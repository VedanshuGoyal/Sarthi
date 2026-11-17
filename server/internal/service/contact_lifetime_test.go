package service

import (
	"context"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// Each side keeps the other's number for two hours after the ride ends —
// for a forgotten bag — and then it's gone from both apps.
func TestContactLifetime_driverSeesTheCustomersNumberUntilTwoHoursAfter(t *testing.T) {
	ended := testNow.Add(-contactLifetime)
	justNow := testNow.Add(-contactLifetime + time.Minute)
	ride := func(id string, status domain.RideStatus) domain.RideBooking {
		rb := openRide(id, testNow.Add(-5*time.Hour), 2, "automatic")
		rb.Booking.Status, rb.Booking.DriverID = status, "auto"
		return rb
	}
	old, recent, cancelled, coming := ride("old", domain.RideStatusCompleted), ride("recent", domain.RideStatusCompleted),
		ride("cancelled", domain.RideStatusCancelled), ride("coming", domain.RideStatusAccepted)
	old.Booking.CompletedAt, recent.Booking.CompletedAt, cancelled.Booking.CancelledAt = &ended, &justNow, &ended
	svc := newRideService(newFakeRideStore(old, recent, cancelled, coming))

	mine, err := svc.MyRides(context.Background(), "auto")
	if err != nil {
		t.Fatalf("MyRides: %v", err)
	}
	want := map[string]string{"old": "", "recent": "+919800000000", "cancelled": "", "coming": "+919800000000"}
	for _, r := range mine {
		if r.Customer == nil || r.Customer.Name != "Asha" || r.Customer.PhoneE164 != want[r.ID] {
			t.Errorf("%s: customer = %+v, want phone %q", r.ID, r.Customer, want[r.ID])
		}
	}
}

func TestContactLifetime_customerSeesTheDriversNumberUntilTwoHoursAfter(t *testing.T) {
	ended := bookingTestNow.Add(-contactLifetime - time.Second)
	recent := bookingTestNow.Add(-time.Hour)
	done := customerRide("done", domain.RideStatusCompleted, "d1")
	done.Booking.CompletedAt = &ended
	fresh := customerRide("fresh", domain.RideStatusCompleted, "d1")
	fresh.Booking.CompletedAt = &recent
	called := customerRide("called-off", domain.RideStatusCancelled, "d1")
	called.Booking.CancelledAt = &ended
	store := &fakeBookingStore{listed: []domain.UserBooking{done, fresh, called}}

	got, err := newTestBookingService(store).ListMine(context.Background(), "u1")
	if err != nil {
		t.Fatalf("ListMine: %v", err)
	}
	want := map[string]string{"done": "", "fresh": "+919800000001", "called-off": ""}
	for _, b := range got {
		if b.Driver == nil || b.Driver.Name != "Ravi" || b.Driver.PhoneE164 != want[b.ID] {
			t.Errorf("%s: driver = %+v, want phone %q", b.ID, b.Driver, want[b.ID])
		}
	}
	// The stored row is untouched; only what's shown changes.
	if store.listed[0].Driver.PhoneE164 == "" {
		t.Error("hiding the number changed the store's copy")
	}
}
