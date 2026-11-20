package repository

import (
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// HUMAN REVIEW REQUIRED: payments (read path). One payment that collected a
// ride and an earlier cancellation fee: both bookings' receipts carry the
// order's whole amount, and its lines are those two bookings — oldest
// first, each with its part and kind. Only the customer's own orders and
// bookings are ever listed.
func TestBookingRepository_PaymentLines_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	bookings, payments := NewBookingRepository(tx), NewPaymentRepository(tx)
	user, other, driver := newTestUser(t, ctx, tx), newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	yesterday := time.Now().Add(-24 * time.Hour)

	ride := rideIn(t, ctx, tx, user, driver, domain.RideStatusCompleted, yesterday, 24000)
	fee := rideIn(t, ctx, tx, user, driver, domain.RideStatusArrived, yesterday.Add(-24*time.Hour), 44000)
	if _, err := bookings.Cancel(ctx, fee, user, "", yesterday, PickupCancel{Allowed: true, FeePaise: 5000}); err != nil {
		t.Fatalf("Cancel: %v", err)
	}
	// Someone else's ride, wrongly put on this customer's order: never shown.
	stranger := rideIn(t, ctx, tx, other, driver, domain.RideStatusCompleted, yesterday, 13900)

	order := domain.PaymentOrder{
		MerchantOrderID: "MOJUD_lines_both", BookingID: ride, UserID: user, AmountPaise: 42900,
		ProviderOrderID: "OMO-lines-both", ExpiresAt: time.Now().Add(time.Hour),
		Items: []domain.PaymentItem{
			{BookingID: ride, AmountPaise: 24000}, {BookingID: fee, AmountPaise: 5000},
			{BookingID: stranger, AmountPaise: 13900},
		},
	}
	if err := payments.InsertOrder(ctx, order); err != nil {
		t.Fatalf("InsertOrder: %v", err)
	}
	if _, err := payments.CompleteOrder(ctx, order, domain.GatewayOrderStatus{
		State: domain.PaymentCompleted, AmountPaise: 42900, TransactionID: "T-lines", PaymentMode: "UPI_INTENT",
	}, 1300, time.Now()); err != nil {
		t.Fatalf("CompleteOrder: %v", err)
	}
	// The other customer's own order, for one ride of theirs.
	theirs := rideIn(t, ctx, tx, other, driver, domain.RideStatusCompleted, yesterday, 24000)
	if err := payments.InsertOrder(ctx, domain.PaymentOrder{
		MerchantOrderID: "MOJUD_lines_theirs", BookingID: theirs, UserID: other, AmountPaise: 24000,
		ProviderOrderID: "OMO-lines-theirs", ExpiresAt: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatalf("InsertOrder(theirs): %v", err)
	}

	// Each receipt names the order and its whole amount.
	for _, id := range []string{ride, fee} {
		ub, err := bookings.FindForUser(ctx, id, user)
		if err != nil {
			t.Fatalf("FindForUser(%s): %v", id, err)
		}
		if p := ub.Payment; p == nil || p.MerchantOrderID != order.MerchantOrderID || p.TotalPaise != 42900 ||
			p.Mode != "UPI_INTENT" {
			t.Errorf("%s: payment = %+v, want order %s for 42900", id, p, order.MerchantOrderID)
		}
	}

	got, err := bookings.PaymentLines(ctx, user, []string{order.MerchantOrderID, "MOJUD_lines_theirs", "MOJUD_lines_none"})
	if err != nil {
		t.Fatalf("PaymentLines: %v", err)
	}
	if len(got) != 1 {
		t.Errorf("orders listed = %v, want only %s", got, order.MerchantOrderID)
	}
	lines := got[order.MerchantOrderID]
	if len(lines) != 2 {
		t.Fatalf("lines = %+v, want the fee and the ride", lines)
	}
	if l := lines[0]; l.BookingID != fee || l.Kind != domain.PaymentLineCancellationFee || l.AmountPaise != 5000 ||
		l.TripType != "roundTrip" || l.ScheduledAt == nil {
		t.Errorf("first line = %+v, want the older fee of 5000", l)
	}
	if l := lines[1]; l.BookingID != ride || l.Kind != domain.PaymentLineRide || l.AmountPaise != 24000 ||
		l.ScheduledAt == nil || !l.ScheduledAt.After(*lines[0].ScheduledAt) {
		t.Errorf("second line = %+v, want the ride of 24000", l)
	}

	// The other customer sees their own order only.
	if got, err := bookings.PaymentLines(ctx, other, []string{order.MerchantOrderID, "MOJUD_lines_theirs"}); err != nil ||
		len(got) != 1 || len(got["MOJUD_lines_theirs"]) != 1 || got["MOJUD_lines_theirs"][0].BookingID != theirs {
		t.Errorf("other customer: %+v, %v; want just their own order", got, err)
	}
	// Nothing asked, nothing read.
	if got, err := bookings.PaymentLines(ctx, user, nil); err != nil || got != nil {
		t.Errorf("no orders: %v, %v", got, err)
	}
}
