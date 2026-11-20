package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/service"
)

// receiptStore lists one paid ride whose payment also paid a cancellation
// fee, with that payment's lines.
type receiptStore struct {
	submitStore
	listed []domain.UserBooking
	lines  map[string][]domain.PaymentLine
}

func (s *receiptStore) ListForUser(context.Context, string, int) ([]domain.UserBooking, error) {
	return s.listed, nil
}

func (s *receiptStore) PaymentLines(context.Context, string, []string) (map[string][]domain.PaymentLine, error) {
	return s.lines, nil
}

// HUMAN REVIEW REQUIRED: payments (read path). GET /me/bookings: a paid
// booking's payment keeps every key the released app reads and adds the
// payment's total and lines — booking, kind, label, amount, nothing more.
func TestListBookings_receiptLinesJSON(t *testing.T) {
	scheduled := time.Date(2026, 11, 17, 4, 0, 0, 0, time.UTC)
	completed := scheduled.Add(2 * time.Hour)
	paidAt := completed.Add(time.Hour)
	feeDay := scheduled.Add(-48 * time.Hour)
	store := &receiptStore{
		listed: []domain.UserBooking{{
			Booking: domain.Booking{
				ID: "bk-ride", UserID: "u1", TripType: service.TripRoundTrip, Status: domain.RideStatusCompleted,
				ScheduledAt: &scheduled, CompletedAt: &completed, FarePaise: 24000,
				PaidAt: &paidAt, PaidPaise: 24000, CommissionPaise: 3120,
				Details: map[string]any{
					"pickup":      map[string]any{"address": "India Gate", "point": map[string]any{"latitude": 28.611, "longitude": 77.2345}},
					"hours":       2.0,
					"scheduledAt": scheduled.Format(time.RFC3339),
					"fare":        240.0,
				},
			},
			Payment: &domain.BookingPayment{
				Mode: "UPI_INTENT", UTR: "412345678901", MerchantOrderID: "MOJUD_ab", PaidAt: paidAt, TotalPaise: 29000,
			},
		}},
		lines: map[string][]domain.PaymentLine{"MOJUD_ab": {
			{BookingID: "bk-fee", Kind: domain.PaymentLineCancellationFee, TripType: service.TripOneWay,
				ScheduledAt: &feeDay, AmountPaise: 5000},
			{BookingID: "bk-ride", Kind: domain.PaymentLineRide, TripType: service.TripRoundTrip,
				ScheduledAt: &scheduled, AmountPaise: 24000},
		}},
	}
	req := httptest.NewRequest(http.MethodGet, "/me/bookings", nil)
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, "u1"))
	rec := httptest.NewRecorder()
	NewBookingHandler(service.NewBookingService(store, nil, nil, nil)).List(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}

	var body struct {
		Bookings []map[string]any `json:"bookings"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || len(body.Bookings) != 1 {
		t.Fatalf("body %s: %v", rec.Body, err)
	}
	b := body.Bookings[0]
	if b["paymentStatus"] != "paid" || b["farePaise"] != 24000.0 || b["paidAt"] == nil {
		t.Errorf("booking keys changed: %v", b)
	}
	payment, _ := b["payment"].(map[string]any)
	for key, want := range map[string]any{
		"mode": "UPI_INTENT", "utr": "412345678901", "merchantOrderId": "MOJUD_ab", "totalPaise": 29000.0,
	} {
		if payment[key] != want {
			t.Errorf("payment.%s = %v, want %v", key, payment[key], want)
		}
	}
	if payment["paidAt"] == nil {
		t.Error("payment.paidAt is missing")
	}
	lines, _ := payment["lines"].([]any)
	if len(lines) != 2 {
		t.Fatalf("payment.lines = %v, want two", payment["lines"])
	}
	first, _ := lines[0].(map[string]any)
	want := map[string]any{
		"bookingId": "bk-fee", "kind": "cancellation_fee", "label": "Cancellation fee · Sun 15 Nov", "amountPaise": 5000.0,
	}
	if len(first) != len(want) {
		t.Errorf("line keys = %v, want exactly %v", first, want)
	}
	for key, w := range want {
		if first[key] != w {
			t.Errorf("lines[0].%s = %v, want %v", key, first[key], w)
		}
	}
	if second, _ := lines[1].(map[string]any); second["kind"] != "ride" || second["label"] != "Round trip · Tue 17 Nov" {
		t.Errorf("lines[1] = %v", second)
	}
}
