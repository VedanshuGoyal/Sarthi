package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// HUMAN REVIEW REQUIRED: payments. Cancelling is free until the driver
// reaches the pickup and costs the fee after; the app must have shown it.
func TestBookingService_CancelAtPickupCharges(t *testing.T) {
	fee := domain.CancellationFeePaise
	zero := int64(0)
	ctx := context.Background()
	setup := func() (*BookingService, *cancelAlerts) {
		store := &fakeBookingStore{listed: []domain.UserBooking{
			customerRide("coming", domain.RideStatusAccepted, "d1"),
			customerRide("waiting", domain.RideStatusArrived, "d1"),
		}}
		svc := newTestBookingService(store)
		alerts := &cancelAlerts{}
		svc.alerts = alerts
		return svc, alerts
	}

	// The app shows what cancelling costs: free on the way, the fee at the pickup.
	svc, _ := setup()
	if got, _ := svc.mine(ctx, "u1", "coming"); got.CancellationFeePaise != 0 {
		t.Errorf("driver on the way: cancellationFeePaise = %d, want 0", got.CancellationFeePaise)
	}
	if got, _ := svc.mine(ctx, "u1", "waiting"); got.CancellationFeePaise != fee {
		t.Errorf("driver at the pickup: cancellationFeePaise = %d, want %d", got.CancellationFeePaise, fee)
	}

	// Before arrival: free, whatever the app agreed to.
	got, err := svc.Cancel(ctx, "u1", "coming", "", &zero)
	if err != nil || got.CancellationFeePaise != 0 || got.PaymentStatus != "" {
		t.Fatalf("Cancel(coming) = %+v, %v; want free", got, err)
	}

	// At the pickup, with the app having shown no fee: refused, nothing changes.
	_, err = svc.Cancel(ctx, "u1", "waiting", "", &zero)
	var feeErr *CancellationFeeError
	if !errors.As(err, &feeErr) || feeErr.FeePaise != fee {
		t.Fatalf("Cancel(waiting, accepted 0) err = %v, want CancellationFeeError{%d}", err, fee)
	}
	if got, _ := svc.mine(ctx, "u1", "waiting"); got.Status != domain.RideStatusArrived {
		t.Errorf("refused cancel changed the ride to %q", got.Status)
	}

	// Agreed to the fee: cancelled, charged, due, and the driver hears of it.
	svc, alerts := setup()
	got, err = svc.Cancel(ctx, "u1", "waiting", "Changed my mind", &fee)
	if err != nil {
		t.Fatalf("Cancel(waiting, accepted fee): %v", err)
	}
	if got.Status != domain.RideStatusCancelled || got.CancellationFeePaise != fee ||
		got.PaymentStatus != domain.RidePaymentDue {
		t.Errorf("cancelled at the pickup = status %q fee %d payment %q; want cancelled, %d, due",
			got.Status, got.CancellationFeePaise, got.PaymentStatus, fee)
	}
	if len(alerts.cancelled) != 1 || alerts.cancelled[0].CancellationFeePaise != fee {
		t.Errorf("driver alerts = %+v, want one carrying the fee", alerts.cancelled)
	}

	// An app from before the fee sends none: it cancels free.
	svc, _ = setup()
	got, err = svc.Cancel(ctx, "u1", "waiting", "", nil)
	if err != nil || got.CancellationFeePaise != 0 || got.PaymentStatus != "" {
		t.Errorf("Cancel(waiting, old app) = fee %d payment %q, %v; want free",
			got.CancellationFeePaise, got.PaymentStatus, err)
	}

	// Payments off: there'd be no way to pay, so no fee.
	svc, _ = setup()
	svc.SetPaymentsEnabled(false)
	if got, _ := svc.mine(ctx, "u1", "waiting"); got.CancellationFeePaise != 0 {
		t.Errorf("payments off: cancellationFeePaise = %d, want 0", got.CancellationFeePaise)
	}
	got, err = svc.Cancel(ctx, "u1", "waiting", "", &zero)
	if err != nil || got.CancellationFeePaise != 0 {
		t.Errorf("payments off: Cancel = fee %d, %v; want free", got.CancellationFeePaise, err)
	}
}

// HUMAN REVIEW REQUIRED: payments. Ending a trip early charges the hourly
// tariff for the time used, never more than booked.
func TestBookingService_EndEarly(t *testing.T) {
	ctx := context.Background()
	started := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC) // 13:30 IST
	driving := customerRide("driving", domain.RideStatusInProgress, "d1")
	driving.Booking.StartedAt = &started
	driving.Booking.FarePaise = 44000 // 4 h booked
	store := &fakeBookingStore{listed: []domain.UserBooking{
		driving, customerRide("coming", domain.RideStatusAccepted, "d1"),
	}}
	svc := newTestBookingService(store)
	alerts := &cancelAlerts{}
	svc.alerts = alerts
	svc.now = func() time.Time { return started.Add(90 * time.Minute) }

	got, err := svc.EndEarly(ctx, "u1", "driving")
	if err != nil {
		t.Fatalf("EndEarly: %v", err)
	}
	// 1 h 30 min → 2 started hours → ₹240.
	if got.Status != domain.RideStatusCompleted || got.FarePaise != 24000 || got.BookedFarePaise != 44000 ||
		got.PaymentStatus != domain.RidePaymentDue {
		t.Errorf("ended trip = status %q fare %d booked %d payment %q; want completed, 24000, 44000, due",
			got.Status, got.FarePaise, got.BookedFarePaise, got.PaymentStatus)
	}
	if len(alerts.ended) != 1 || alerts.ended[0].DriverID != "d1" || alerts.ended[0].FarePaise != 24000 {
		t.Errorf("driver alerts = %+v, want one for d1 at 24000", alerts.ended)
	}

	// Not in progress (any more): refused.
	for _, id := range []string{"driving", "coming"} {
		if _, err := svc.EndEarly(ctx, "u1", id); !errors.Is(err, ErrCannotEnd) ||
			!errors.Is(err, repository.ErrBookingStateConflict) {
			t.Errorf("EndEarly(%s) err = %v, want ErrCannotEnd", id, err)
		}
	}
	if _, err := svc.EndEarly(ctx, "u2", "driving"); !errors.Is(err, repository.ErrBookingNotFound) {
		t.Errorf("EndEarly(other user) err = %v, want ErrBookingNotFound", err)
	}
}

func TestChargeForTimeUsed(t *testing.T) {
	day := time.Date(2026, 10, 24, 10, 0, 0, 0, ist)
	night := time.Date(2026, 10, 24, 21, 30, 0, 0, ist)
	standard := tripPlan{}
	luxury := tripPlan{Car: &domain.RideCar{CarType: string(domain.CarTypeLuxury)}}
	for _, tc := range []struct {
		name    string
		plan    tripPlan
		started time.Time
		used    time.Duration
		booked  int64
		want    int64
	}{
		{"a few minutes is the first hour", standard, day, 5 * time.Minute, 44000, 13900},
		{"exactly an hour", standard, day, time.Hour, 44000, 13900},
		{"a minute over starts the second", standard, day, 61 * time.Minute, 44000, 24000},
		{"three started hours", standard, day, 2*time.Hour + 10*time.Minute, 44000, 34000},
		{"never more than booked", standard, day, 6 * time.Hour, 44000, 44000},
		{"luxury tariff", luxury, day, 30 * time.Minute, 76000, 19600},
		// 21:30 for 2 started hours: 22:00–23:30 is night, two part hours —
		// ₹240 + ₹50 + 2 × ₹24.
		{"night surcharge for the hours used", standard, night, 100 * time.Minute, 60000, 33800},
		{"clock skew counts as the first hour", standard, day, -time.Minute, 44000, 13900},
	} {
		got := chargeForTimeUsed(tc.plan, tc.booked, tc.started, tc.started.Add(tc.used))
		if got != tc.want {
			t.Errorf("%s: got %d, want %d", tc.name, got, tc.want)
		}
	}
}

// HUMAN REVIEW REQUIRED: payments. A cancellation's fee is paid through the
// same checkout as a ride; a free one has nothing to pay.
func TestCheckout_cancellationFee(t *testing.T) {
	charged := domain.Booking{ID: "b-fee", UserID: "u1", DriverID: "d1",
		Status: domain.RideStatusCancelled, FarePaise: 44000, CancellationFeePaise: domain.CancellationFeePaise}
	free := domain.Booking{ID: "b-free", UserID: "u1", DriverID: "d1",
		Status: domain.RideStatusCancelled, FarePaise: 44000}
	store := newFakePaymentStore(charged, free)
	svc := newPayments(store, &fakeGateway{}, &recordingPaymentAlerts{}, 1300)
	ctx := context.Background()

	if _, err := svc.Checkout(ctx, "u1", "b-free"); !errors.Is(err, ErrNotPayable) {
		t.Errorf("free cancellation: err = %v, want ErrNotPayable", err)
	}
	c, err := svc.Checkout(ctx, "u1", "b-fee")
	if err != nil {
		t.Fatalf("Checkout(fee): %v", err)
	}
	if c.AmountPaise != domain.CancellationFeePaise {
		t.Errorf("checkout amount = %d, want the fee %d, not the fare", c.AmountPaise, domain.CancellationFeePaise)
	}
}

func TestBookingAmountDueAndPaymentStatus(t *testing.T) {
	paid := time.Now()
	for _, tc := range []struct {
		name   string
		b      domain.Booking
		due    int64
		status domain.RidePaymentStatus
	}{
		{"in progress", domain.Booking{Status: domain.RideStatusInProgress, FarePaise: 100}, 0, ""},
		{"completed", domain.Booking{Status: domain.RideStatusCompleted, FarePaise: 100}, 100, domain.RidePaymentDue},
		{"free cancel", domain.Booking{Status: domain.RideStatusCancelled, FarePaise: 100}, 0, ""},
		{"fee due", domain.Booking{Status: domain.RideStatusCancelled, FarePaise: 100, CancellationFeePaise: 5000},
			5000, domain.RidePaymentDue},
		{"fee paid", domain.Booking{Status: domain.RideStatusCancelled, CancellationFeePaise: 5000, PaidAt: &paid},
			5000, domain.RidePaymentPaid},
	} {
		if got := tc.b.AmountDue(); got != tc.due {
			t.Errorf("%s: AmountDue = %d, want %d", tc.name, got, tc.due)
		}
		if got := tc.b.PaymentStatus(); got != tc.status {
			t.Errorf("%s: PaymentStatus = %q, want %q", tc.name, got, tc.status)
		}
	}
}
