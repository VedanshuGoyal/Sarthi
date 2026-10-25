package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// fakeBookingStore records the last insert and returns a canned booking, or a
// preset error.
type fakeBookingStore struct {
	insertHit bool
	params    repository.InsertBookingParams
	got       domain.Booking
	err       error
	listed    []domain.UserBooking
}

func (f *fakeBookingStore) ListForUser(context.Context, string, int) ([]domain.UserBooking, error) {
	return f.listed, f.err
}

func (f *fakeBookingStore) Insert(_ context.Context, p repository.InsertBookingParams) (domain.Booking, error) {
	if f.err != nil {
		return domain.Booking{}, f.err
	}
	f.insertHit = true
	f.params = p
	f.got = domain.Booking{
		ID:       "bk-1",
		UserID:   p.UserID,
		TripType: p.TripType,
		Details:  p.Details,
	}
	return f.got, nil
}

// roundTripDetails is a round-trip payload as the customer app sends it.
func roundTripDetails() map[string]any {
	return map[string]any{
		"pickup": map[string]any{
			"address": "India Gate, New Delhi",
			"point":   map[string]any{"latitude": 28.611, "longitude": 77.2345},
		},
		"hours":       4.0,
		"scheduledAt": "2026-10-24T13:30:00.000",
		"car": map[string]any{
			"registration": "DL01AB1234", "carType": "sedan", "transmission": "automatic",
		},
		"fare": 440.0,
	}
}

// bookingTestNow is two hours before roundTripDetails' start (08:00 UTC).
var bookingTestNow = time.Date(2026, 10, 24, 6, 0, 0, 0, time.UTC)

func newTestBookingService(store BookingStore) *BookingService {
	svc := NewBookingService(store)
	svc.now = func() time.Time { return bookingTestNow }
	return svc
}

func TestBookingService_Record_persists(t *testing.T) {
	store := &fakeBookingStore{}
	svc := newTestBookingService(store)

	// A leading/trailing space on the trip type is trimmed before storing.
	got, err := svc.Record(context.Background(), "u1", " roundTrip ", roundTripDetails())
	if err != nil {
		t.Fatalf("Record: %v", err)
	}
	if !store.insertHit {
		t.Fatal("expected Insert to be called")
	}
	if store.got.TripType != "roundTrip" {
		t.Errorf("stored tripType = %q, want roundTrip", store.got.TripType)
	}
	if got.ID != "bk-1" {
		t.Errorf("returned booking id = %q, want bk-1", got.ID)
	}
	// The wall-clock time with no offset is IST: 13:30 IST is 08:00 UTC.
	if want := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC); !store.params.ScheduledAt.Equal(want) {
		t.Errorf("scheduledAt = %v, want %v", store.params.ScheduledAt, want)
	}
	if store.params.FarePaise != 44000 || store.params.FareEstimated {
		t.Errorf("fare = %d (estimated %v), want quoted 44000", store.params.FarePaise, store.params.FareEstimated)
	}
}

func TestBookingService_Record_rejectsInvalid(t *testing.T) {
	store := &fakeBookingStore{}
	svc := newTestBookingService(store)
	details := map[string]any{"hours": 4}

	if _, err := svc.Record(context.Background(), "u1", "  ", details); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("blank tripType: err = %v, want ErrInvalidBooking", err)
	}
	if _, err := svc.Record(context.Background(), "u1", "roundTrip", nil); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("nil details: err = %v, want ErrInvalidBooking", err)
	}
	// Details a driver couldn't read (no pickup coordinates) are refused.
	if _, err := svc.Record(context.Background(), "u1", "roundTrip", details); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("unreadable details: err = %v, want ErrInvalidBooking", err)
	}
	if store.insertHit {
		t.Error("Insert must not be called for an invalid booking")
	}
}

func TestBookingService_Record_propagatesStoreError(t *testing.T) {
	wantErr := errors.New("db down")
	svc := newTestBookingService(&fakeBookingStore{err: wantErr})

	if _, err := svc.Record(context.Background(), "u1", "roundTrip", roundTripDetails()); !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}

func TestBookingService_ListMine_showsStartCodeOnlyWhileDriverIsComing(t *testing.T) {
	at := time.Date(2026, 10, 26, 3, 30, 0, 0, time.UTC)
	booking := func(id string, status domain.RideStatus) domain.Booking {
		return domain.Booking{
			ID: id, TripType: TripRoundTrip, Details: roundTripDetails(),
			Status: status, ScheduledAt: &at, FarePaise: 44000, StartOTP: "4821",
		}
	}
	driver := &domain.RideDriver{Name: "Ravi", PhoneE164: "+919800000001"}
	store := &fakeBookingStore{listed: []domain.UserBooking{
		{Booking: booking("open", domain.RideStatusRequested)},
		{Booking: booking("coming", domain.RideStatusAccepted), Driver: driver},
		{Booking: booking("waiting", domain.RideStatusArrived), Driver: driver},
		{Booking: booking("driving", domain.RideStatusInProgress), Driver: driver},
		{Booking: domain.Booking{ID: "junk", TripType: TripRoundTrip, Details: map[string]any{}}},
	}}
	got, err := newTestBookingService(store).ListMine(context.Background(), "u1")
	if err != nil {
		t.Fatalf("ListMine: %v", err)
	}
	if len(got) != 4 {
		t.Fatalf("bookings = %d, want 4 (unreadable one skipped)", len(got))
	}
	want := map[string]string{"open": "", "coming": "4821", "waiting": "4821", "driving": ""}
	for _, b := range got {
		if b.StartOTP != want[b.ID] {
			t.Errorf("%s: startOtp = %q, want %q", b.ID, b.StartOTP, want[b.ID])
		}
	}
	if got[1].Driver == nil || got[1].Driver.Name != "Ravi" {
		t.Errorf("driver = %+v, want Ravi", got[1].Driver)
	}
	if got[0].Pickup.Address != "India Gate, New Delhi" || got[0].FarePaise != 44000 {
		t.Errorf("booking = %+v", got[0])
	}
}

func TestBookingService_Record_rejectsTooSoon(t *testing.T) {
	store := &fakeBookingStore{}
	svc := newTestBookingService(store)
	start := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC) // roundTripDetails

	// 30 minutes ahead: it would close to drivers the moment it's booked.
	svc.now = func() time.Time { return start.Add(-30 * time.Minute) }
	if _, err := svc.Record(context.Background(), "u1", "roundTrip", roundTripDetails()); !errors.Is(err, ErrBookingTooSoon) {
		t.Errorf("30 min ahead: err = %v, want ErrBookingTooSoon", err)
	}
	if store.insertHit {
		t.Error("Insert must not be called for a too-soon booking")
	}

	// The earliest slot, submitted a couple of minutes later: still accepted.
	svc.now = func() time.Time { return start.Add(-43 * time.Minute) }
	if _, err := svc.Record(context.Background(), "u1", "roundTrip", roundTripDetails()); err != nil {
		t.Errorf("43 min ahead: err = %v, want nil", err)
	}
}

func TestBookingService_ListMine_expiresUntakenRequests(t *testing.T) {
	at := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC)
	booking := func(id string, status domain.RideStatus) domain.UserBooking {
		return domain.UserBooking{Booking: domain.Booking{
			ID: id, TripType: TripRoundTrip, Details: roundTripDetails(),
			Status: status, ScheduledAt: &at,
		}}
	}
	store := &fakeBookingStore{listed: []domain.UserBooking{
		booking("open", domain.RideStatusRequested),
		booking("taken", domain.RideStatusAccepted),
	}}
	svc := newTestBookingService(store)

	statuses := func() map[string]domain.RideStatus {
		got, err := svc.ListMine(context.Background(), "u1")
		if err != nil {
			t.Fatalf("ListMine: %v", err)
		}
		out := map[string]domain.RideStatus{}
		for _, b := range got {
			out[b.ID] = b.Status
		}
		return out
	}

	// Exactly 30 minutes before the start: still open to drivers.
	svc.now = func() time.Time { return at.Add(-30 * time.Minute) }
	if got := statuses(); got["open"] != domain.RideStatusRequested {
		t.Errorf("at the cutoff: open = %q, want requested", got["open"])
	}

	// A minute later nobody can take it — the customer sees it expired; a
	// ride a driver already took is untouched.
	svc.now = func() time.Time { return at.Add(-29 * time.Minute) }
	got := statuses()
	if got["open"] != domain.RideStatusExpired {
		t.Errorf("past the cutoff: open = %q, want expired", got["open"])
	}
	if got["taken"] != domain.RideStatusAccepted {
		t.Errorf("past the cutoff: taken = %q, want accepted", got["taken"])
	}
}
