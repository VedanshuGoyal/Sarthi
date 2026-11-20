package service

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// paidBy marks ub paid by gateway order order, which came to total.
func paidBy(ub domain.UserBooking, order string, total int64) domain.UserBooking {
	at := time.Date(2026, 11, 18, 6, 0, 0, 0, time.UTC)
	ub.Booking.PaidAt = &at
	ub.Payment = &domain.BookingPayment{
		Mode: "UPI_INTENT", UTR: "412345678901", MerchantOrderID: order, PaidAt: at, TotalPaise: total,
	}
	return ub
}

// HUMAN REVIEW REQUIRED: payments (read path). One payment that collected a
// ride and an earlier cancellation fee shows, on both bookings' receipts,
// the whole amount and a labelled line per booking. A payment for one ride
// lists just that ride; a ride settled by hand and an unpaid one list
// nothing. The store is asked once, for each order once.
func TestBookingService_receiptListsEveryBookingThePaymentPaid(t *testing.T) {
	ride := customerRide("ride-a", domain.RideStatusCompleted, "d1")
	ride.Booking.FarePaise = 44000
	fee := customerRide("fee-b", domain.RideStatusCancelled, "d2")
	fee.Booking.CancellationFeePaise = domain.CancellationFeePaise
	solo := customerRide("solo", domain.RideStatusCompleted, "d1")
	solo.Booking.FarePaise = 24000
	cash := customerRide("cash", domain.RideStatusCompleted, "d1")
	cash.Booking.FarePaise = 24000
	cash.Booking.PaidAt = &time.Time{}
	cash.Payment = &domain.BookingPayment{Mode: "CASH"}
	due := customerRide("due", domain.RideStatusCompleted, "d1")
	due.Booking.FarePaise = 24000

	// 01:30 IST on Tue 17 Nov is still 16 Nov in UTC: the label is IST's day.
	rideDay := time.Date(2026, 11, 16, 20, 0, 0, 0, time.UTC)
	feeDay := time.Date(2026, 11, 15, 6, 0, 0, 0, time.UTC)
	store := &fakeBookingStore{
		listed: []domain.UserBooking{
			paidBy(ride, "MOJUD_ab", 49000), paidBy(fee, "MOJUD_ab", 49000),
			paidBy(solo, "MOJUD_solo", 24000), cash, due,
		},
		lines: map[string][]domain.PaymentLine{
			"MOJUD_ab": {
				{BookingID: "fee-b", Kind: domain.PaymentLineCancellationFee, TripType: TripOneWay,
					ScheduledAt: &feeDay, AmountPaise: 5000},
				{BookingID: "ride-a", Kind: domain.PaymentLineRide, TripType: TripRoundTrip,
					ScheduledAt: &rideDay, AmountPaise: 44000},
			},
			"MOJUD_solo": {
				{BookingID: "solo", Kind: domain.PaymentLineRide, TripType: TripMultiStop, AmountPaise: 24000},
			},
		},
	}
	svc := newTestBookingService(store)
	ctx := context.Background()

	got, err := svc.ListMine(ctx, "u1")
	if err != nil {
		t.Fatalf("ListMine: %v", err)
	}
	if want := [][]string{{"MOJUD_ab", "MOJUD_solo"}}; len(store.linesAsked) != 1 ||
		!slices.Equal(store.linesAsked[0], want[0]) {
		t.Errorf("PaymentLines asked for %v, want %v", store.linesAsked, want)
	}
	byID := map[string]domain.CustomerBooking{}
	for _, b := range got {
		byID[b.ID] = b
	}
	wantTogether := []domain.PaymentLine{
		{BookingID: "fee-b", Kind: domain.PaymentLineCancellationFee, Label: "Cancellation fee · Sun 15 Nov", AmountPaise: 5000},
		{BookingID: "ride-a", Kind: domain.PaymentLineRide, Label: "Round trip · Tue 17 Nov", AmountPaise: 44000},
	}
	for _, id := range []string{"ride-a", "fee-b"} {
		p := byID[id].Payment
		if p == nil || p.TotalPaise != 49000 || p.MerchantOrderID != "MOJUD_ab" {
			t.Fatalf("%s: payment = %+v, want order MOJUD_ab for 49000", id, p)
		}
		if !sameLines(p.Lines, wantTogether) {
			t.Errorf("%s: lines = %+v, want %+v", id, p.Lines, wantTogether)
		}
	}
	if p := byID["solo"].Payment; p == nil || p.TotalPaise != 24000 ||
		!sameLines(p.Lines, []domain.PaymentLine{{BookingID: "solo", Kind: domain.PaymentLineRide, Label: "Multi-stop", AmountPaise: 24000}}) {
		t.Errorf("solo: payment = %+v, want its one line", p)
	}
	if p := byID["cash"].Payment; p == nil || p.Mode != "CASH" || p.Lines != nil || p.TotalPaise != 0 {
		t.Errorf("cash: payment = %+v, want CASH with no lines", p)
	}
	if p := byID["due"].Payment; p != nil {
		t.Errorf("due: payment = %+v, want none", p)
	}
	// The store's own rows are left alone: each receipt is a copy.
	if store.listed[0].Payment.Lines != nil {
		t.Errorf("the store's payment was changed: %+v", store.listed[0].Payment)
	}

	// One booking reads the same.
	one, err := svc.Get(ctx, "u1", "fee-b")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if p := one.Payment; p == nil || !sameLines(p.Lines, wantTogether) {
		t.Errorf("Get: payment = %+v, want the two lines", p)
	}
}

// A receipt whose lines can't be read still shows the payment: the list
// doesn't fail over them.
func TestBookingService_receiptWithoutLinesWhenTheyCantBeRead(t *testing.T) {
	ride := customerRide("ride-a", domain.RideStatusCompleted, "d1")
	ride.Booking.FarePaise = 44000
	store := &fakeBookingStore{
		listed:   []domain.UserBooking{paidBy(ride, "MOJUD_a", 44000)},
		linesErr: errors.New("connection reset"),
	}
	got, err := newTestBookingService(store).ListMine(context.Background(), "u1")
	if err != nil {
		t.Fatalf("ListMine: %v", err)
	}
	if len(got) != 1 || got[0].Payment == nil || got[0].Payment.MerchantOrderID != "MOJUD_a" ||
		got[0].Payment.Lines != nil {
		t.Errorf("got %+v, want the receipt without lines", got)
	}
}

// No paid booking, no lines read.
func TestBookingService_noReceiptsNoLinesRead(t *testing.T) {
	store := &fakeBookingStore{listed: []domain.UserBooking{customerRide("open", domain.RideStatusRequested, "")}}
	if _, err := newTestBookingService(store).ListMine(context.Background(), "u1"); err != nil {
		t.Fatalf("ListMine: %v", err)
	}
	if len(store.linesAsked) != 0 {
		t.Errorf("PaymentLines asked for %v, want no call", store.linesAsked)
	}
}

func TestPaymentLineLabel(t *testing.T) {
	day := time.Date(2026, 11, 16, 20, 0, 0, 0, time.UTC) // Tue 17 Nov, 01:30 IST
	for _, tc := range []struct {
		line domain.PaymentLine
		want string
	}{
		{domain.PaymentLine{Kind: domain.PaymentLineRide, TripType: TripRoundTrip, ScheduledAt: &day}, "Round trip · Tue 17 Nov"},
		{domain.PaymentLine{Kind: domain.PaymentLineRide, TripType: TripOneWay, ScheduledAt: &day}, "One way · Tue 17 Nov"},
		{domain.PaymentLine{Kind: domain.PaymentLineRide, TripType: TripMultiStop, ScheduledAt: &day}, "Multi-stop · Tue 17 Nov"},
		{domain.PaymentLine{Kind: domain.PaymentLineCancellationFee, TripType: TripRoundTrip, ScheduledAt: &day}, "Cancellation fee · Tue 17 Nov"},
		{domain.PaymentLine{Kind: domain.PaymentLineRide, TripType: "teleport"}, "Ride"},
	} {
		if got := paymentLineLabel(tc.line); got != tc.want {
			t.Errorf("paymentLineLabel(%+v) = %q, want %q", tc.line, got, tc.want)
		}
	}
}

// sameLines compares the lines a customer sees: booking, kind, label and
// amount.
func sameLines(got, want []domain.PaymentLine) bool {
	return slices.EqualFunc(got, want, func(a, b domain.PaymentLine) bool {
		return a.BookingID == b.BookingID && a.Kind == b.Kind && a.Label == b.Label && a.AmountPaise == b.AmountPaise
	})
}
