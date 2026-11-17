package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// --- POST /me/bookings: payment due and repeats ---

// submitStore is a BookingStore for the submit route: an optional unpaid
// ride, and an optional booking a submit repeats.
type submitStore struct {
	unpaid  string
	repeat  *domain.Booking
	gotKey  string
	inserts int
}

func (s *submitStore) Insert(_ context.Context, p repository.InsertBookingParams) (domain.Booking, bool, error) {
	s.gotKey = p.IdempotencyKey
	if s.repeat != nil {
		return *s.repeat, true, nil
	}
	s.inserts++
	return domain.Booking{ID: "bk-new", UserID: p.UserID, TripType: p.TripType, Details: p.Details}, false, nil
}

func (s *submitStore) UnpaidRide(context.Context, string, int64) (string, error) {
	return s.unpaid, nil
}
func (s *submitStore) ListForUser(context.Context, string, int) ([]domain.UserBooking, error) {
	return nil, nil
}
func (s *submitStore) FindForUser(context.Context, string, string) (domain.UserBooking, error) {
	return domain.UserBooking{}, repository.ErrBookingNotFound
}
func (s *submitStore) Cancel(context.Context, string, string, string, time.Time) (domain.Booking, error) {
	return domain.Booking{}, repository.ErrBookingStateConflict
}
func (s *submitStore) RateDriver(context.Context, string, string, domain.RideRating) error {
	return nil
}
func (s *submitStore) DriverBusyElsewhere(context.Context, string, string) (bool, error) {
	return false, nil
}

// submitBooking posts a round trip two days out, as user u1, with key.
func submitBooking(t *testing.T, store *submitStore, key string) *httptest.ResponseRecorder {
	t.Helper()
	start := time.Now().Add(48 * time.Hour).In(time.FixedZone("IST", 5*60*60+30*60))
	start = time.Date(start.Year(), start.Month(), start.Day(), 10, 0, 0, 0, start.Location())
	body := `{"tripType":"roundTrip","details":{"pickup":{"address":"India Gate",` +
		`"point":{"latitude":28.611,"longitude":77.2345}},` +
		`"hours":2,"scheduledAt":"` + start.Format("2006-01-02T15:04:05") + `",` +
		`"car":{"registration":"DL01AB1234","carType":"sedan","transmission":"automatic"},"fare":240}}`
	req := httptest.NewRequest(http.MethodPost, "/me/bookings", strings.NewReader(body))
	if key != "" {
		req.Header.Set("Idempotency-Key", key)
	}
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, "u1"))
	rec := httptest.NewRecorder()
	NewBookingHandler(service.NewBookingService(store, nil, nil, nil)).Submit(rec, req)
	return rec
}

func TestSubmitBooking_paymentDueNamesTheRide(t *testing.T) {
	store := &submitStore{unpaid: "bk-unpaid"}
	rec := submitBooking(t, store, "")
	if rec.Code != http.StatusConflict {
		t.Fatalf("status %d, want 409: %s", rec.Code, rec.Body)
	}
	var body struct{ Error, Code, BookingID string }
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Code != "payment_due" || body.BookingID != "bk-unpaid" || body.Error == "" {
		t.Errorf("body = %s", rec.Body)
	}
	if store.inserts != 0 {
		t.Error("a booking was stored")
	}
}

func TestSubmitBooking_newThenRepeat(t *testing.T) {
	store := &submitStore{}
	rec := submitBooking(t, store, "key-1")
	if rec.Code != http.StatusAccepted || !strings.Contains(rec.Body.String(), `"id":"bk-new"`) {
		t.Fatalf("new booking: %d %s", rec.Code, rec.Body)
	}
	if store.gotKey != "key-1" {
		t.Errorf("Idempotency-Key reached the store as %q", store.gotKey)
	}
	if strings.Contains(rec.Body.String(), "duplicate") {
		t.Errorf("a new booking is marked duplicate: %s", rec.Body)
	}

	store.repeat = &domain.Booking{ID: "bk-first"}
	rec = submitBooking(t, store, "key-1")
	if rec.Code != http.StatusOK {
		t.Fatalf("repeat: status %d, want 200: %s", rec.Code, rec.Body)
	}
	var body bookingResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body.ID != "bk-first" || !body.Duplicate {
		t.Errorf("repeat body = %s", rec.Body)
	}
}

// --- back-office booking tools ---

type apiOpsBookings struct {
	rows map[string]*domain.AdminBookingRow
}

func (f *apiOpsBookings) ListForAdmin(context.Context, repository.AdminBookingFilter) ([]domain.AdminBookingRow, error) {
	var out []domain.AdminBookingRow
	for _, r := range f.rows {
		out = append(out, *r)
	}
	return out, nil
}

func (f *apiOpsBookings) FindForAdmin(_ context.Context, id string) (domain.AdminBookingRow, error) {
	if r, ok := f.rows[id]; ok {
		return *r, nil
	}
	return domain.AdminBookingRow{}, repository.ErrBookingNotFound
}

func (f *apiOpsBookings) CancelByOps(_ context.Context, id, reason string, at time.Time) (domain.Booking, error) {
	r, ok := f.rows[id]
	if !ok {
		return domain.Booking{}, repository.ErrBookingNotFound
	}
	if r.Booking.Status == domain.RideStatusCompleted {
		return domain.Booking{}, repository.ErrBookingStateConflict
	}
	r.Booking.Status, r.Booking.CancelledBy, r.Booking.CancelReason, r.Booking.CancelledAt =
		domain.RideStatusCancelled, domain.CancelledByOps, reason, &at
	return r.Booking, nil
}

type apiOpsPayments struct{ bookings *apiOpsBookings }

func (f *apiOpsPayments) SettleByHand(_ context.Context, id string, mode domain.SettleMode, note string, at time.Time) (domain.Booking, error) {
	r, ok := f.bookings.rows[id]
	if !ok {
		return domain.Booking{}, repository.ErrBookingNotFound
	}
	if r.Booking.Status != domain.RideStatusCompleted || r.Booking.PaidAt != nil {
		return domain.Booking{}, repository.ErrBookingStateConflict
	}
	r.Booking.PaidAt, r.PaidMode, r.PaidNote = &at, string(mode), note
	return r.Booking, nil
}

func (f *apiOpsPayments) PaymentAttention(context.Context, time.Time, int) (domain.PaymentAttention, error) {
	return domain.PaymentAttention{PaidTwice: []domain.AttentionOrder{{MerchantOrderID: "MOJUD_2", BookingID: "b1", PaidBy: "MOJUD_1"}}}, nil
}

type apiAudit struct{ actions []domain.AdminAction }

func (f *apiAudit) RecordAction(_ context.Context, a domain.AdminAction) (domain.AdminAction, error) {
	a.ID = int64(len(f.actions) + 1)
	f.actions = append(f.actions, a)
	return a, nil
}

func (f *apiAudit) RecentActions(context.Context, string, int) ([]domain.AdminAction, error) {
	return f.actions, nil
}

type apiRides struct{}

func (apiRides) FindByID(context.Context, string) (domain.RideBooking, error) {
	return domain.RideBooking{}, repository.ErrRideNotFound
}
func (apiRides) ListForDriver(context.Context, string, int) ([]domain.RideBooking, error) {
	return nil, nil
}
func (apiRides) Accept(context.Context, string, string, time.Time, string) (domain.RideBooking, error) {
	return domain.RideBooking{}, repository.ErrRideUnavailable
}

type apiProfiles struct{}

func (apiProfiles) FindProfile(context.Context, string) (domain.DriverProfile, error) {
	return domain.DriverProfile{}, repository.ErrDriverNotFound
}

func opsHandler(store *fakePayoutStore) (*AdminHandler, *apiOpsBookings, *apiAudit) {
	completed := time.Date(2026, 11, 16, 10, 0, 0, 0, time.UTC)
	bookings := &apiOpsBookings{rows: map[string]*domain.AdminBookingRow{
		"done": {Booking: domain.Booking{ID: "done", TripType: "roundTrip", Status: domain.RideStatusCompleted,
			CompletedAt: &completed, FarePaise: 24000, Details: map[string]any{}}},
		"open": {Booking: domain.Booking{ID: "open", TripType: "roundTrip", Status: domain.RideStatusRequested,
			Details: map[string]any{}}},
	}}
	audit := &apiAudit{}
	ops := service.NewOpsService(service.OpsDeps{
		Bookings: bookings, Rides: apiRides{}, Payments: &apiOpsPayments{bookings: bookings},
		Profiles: apiProfiles{}, Audit: audit,
	})
	return NewAdminHandler(service.NewPayoutService(store, plainOpener{}), nil, nil, nil, ops), bookings, audit
}

func adminCall(h http.HandlerFunc, method, path, id, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("X-Admin-Actor", "Asha")
	if id != "" {
		req.SetPathValue("id", id)
	}
	rec := httptest.NewRecorder()
	h(rec, req)
	return rec
}

func TestAdminSettle_writesTheModeAndAudits(t *testing.T) {
	h, bookings, audit := opsHandler(&fakePayoutStore{})
	rec := adminCall(h.SettleBooking, http.MethodPost, "/admin/bookings/done/settle", "done",
		`{"mode":"waived","reason":"Driver no-show refund"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	if r := bookings.rows["done"]; r.Booking.PaidAt == nil || r.PaidMode != "waived" {
		t.Errorf("row = %+v", r)
	}
	if !strings.Contains(rec.Body.String(), `"paidMode":"waived"`) {
		t.Errorf("body = %s", rec.Body)
	}
	if len(audit.actions) != 1 || audit.actions[0].Actor != "Asha" || audit.actions[0].Action != domain.ActionBookingSettle {
		t.Errorf("audit = %+v", audit.actions)
	}

	// Settling again, an unknown mode, an unknown booking.
	for _, tc := range []struct {
		id, body string
		want     int
		code     string
	}{
		{"done", `{"mode":"cash","reason":"again"}`, http.StatusConflict, "booking_state"},
		{"done", `{"mode":"card","reason":"x"}`, http.StatusBadRequest, "invalid_request"},
		{"open", `{"mode":"cash"}`, http.StatusBadRequest, "invalid_request"},
		{"nope", `{"mode":"cash","reason":"x"}`, http.StatusNotFound, "booking_not_found"},
		{"done", `{"mode":"cash","reason":"x","extra":1}`, http.StatusBadRequest, "invalid_request"},
	} {
		rec := adminCall(h.SettleBooking, http.MethodPost, "/admin/bookings/x/settle", tc.id, tc.body)
		var body struct{ Code string }
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if rec.Code != tc.want || body.Code != tc.code {
			t.Errorf("%s %s: %d %s, want %d %s", tc.id, tc.body, rec.Code, rec.Body, tc.want, tc.code)
		}
	}
}

func TestAdminCancelAndAssign_errors(t *testing.T) {
	h, _, audit := opsHandler(&fakePayoutStore{})
	if rec := adminCall(h.CancelBooking, http.MethodPost, "/", "open", `{"reason":"Customer asked by phone"}`); rec.Code != http.StatusOK ||
		!strings.Contains(rec.Body.String(), `"cancelledBy":"ops"`) {
		t.Errorf("cancel: %d %s", rec.Code, rec.Body)
	}
	if rec := adminCall(h.CancelBooking, http.MethodPost, "/", "done", `{"reason":"x"}`); rec.Code != http.StatusConflict {
		t.Errorf("cancel completed: %d %s", rec.Code, rec.Body)
	}
	if rec := adminCall(h.AssignBooking, http.MethodPost, "/", "open", `{"driverId":"not-a-uuid"}`); rec.Code != http.StatusBadRequest {
		t.Errorf("assign bad id: %d %s", rec.Code, rec.Body)
	}
	if rec := adminCall(h.AssignBooking, http.MethodPost, "/", "open",
		`{"driverId":"00000000-0000-4000-8000-000000000001"}`); rec.Code != http.StatusNotFound ||
		!strings.Contains(rec.Body.String(), "driver_not_found") {
		t.Errorf("assign unknown driver: %d %s", rec.Code, rec.Body)
	}
	if len(audit.actions) != 1 {
		t.Errorf("audit = %+v, want only the successful cancel", audit.actions)
	}
}

func TestAdminBookingsAndAttention(t *testing.T) {
	h, _, _ := opsHandler(&fakePayoutStore{})
	rec := adminCall(h.AdminBookings, http.MethodGet, "/admin/bookings?status=completed&date=2026-11-16", "", "")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"bookings":[`) ||
		rec.Header().Get("Cache-Control") != "no-store" {
		t.Errorf("bookings: %d %s", rec.Code, rec.Body)
	}
	if rec := adminCall(h.AdminBookings, http.MethodGet, "/admin/bookings?status=lost", "", ""); rec.Code != http.StatusBadRequest {
		t.Errorf("bad status: %d", rec.Code)
	}
	rec = adminCall(h.PaymentAttention, http.MethodGet, "/admin/payments/attention", "", "")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"paidBy":"MOJUD_1"`) ||
		!strings.Contains(rec.Body.String(), `"stalePending":[]`) {
		t.Errorf("attention: %d %s", rec.Code, rec.Body)
	}
}

// A recorded payout is audited with what it covered.
func TestRecordPayout_isAudited(t *testing.T) {
	h, _, audit := opsHandler(&fakePayoutStore{})
	rec := postPayout(h, `{"driverId":"d1","reference":"UTR9","asOf":"2026-11-10T12:00:00Z"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	if len(audit.actions) != 1 {
		t.Fatalf("audit = %+v", audit.actions)
	}
	a := audit.actions[0]
	if a.Action != domain.ActionPayoutRecord || a.Target != "p1" || a.Details["reference"] != "UTR9" ||
		a.Details["amountPaise"] != int64(13050) {
		t.Errorf("audit row = %+v", a)
	}
}

// --- GET /driver/payouts ---

func TestDriverPayouts_listsOnlyTheirs(t *testing.T) {
	at := time.Date(2026, 11, 10, 12, 0, 0, 0, time.UTC)
	store := &fakePayoutStore{recorded: []domain.DriverPayout{
		{ID: "p1", DriverID: "d1", AmountPaise: 13050, Rides: 2, Reference: "UTR1", CreatedAt: at},
		{ID: "p2", DriverID: "d2", AmountPaise: 999, Rides: 1, Reference: "UTR2", CreatedAt: at},
	}}
	h := NewDriverMoneyHandler(service.NewPayoutService(store, plainOpener{}))
	for _, tc := range []struct{ driver, want string }{
		{"d1", `"reference":"UTR1"`},
		{"d3", `"payouts":[]`},
	} {
		req := httptest.NewRequest(http.MethodGet, "/driver/payouts", nil)
		req = req.WithContext(context.WithValue(req.Context(), userIDKey, tc.driver))
		rec := httptest.NewRecorder()
		h.Payouts(rec, req)
		if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), tc.want) || strings.Contains(rec.Body.String(), "UTR2") {
			t.Errorf("%s: %d %s", tc.driver, rec.Code, rec.Body)
		}
	}
}
