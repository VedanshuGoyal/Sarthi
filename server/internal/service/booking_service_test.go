package service

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/memstore"
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

// find returns the listed booking id of userID, as the repository scopes it.
func (f *fakeBookingStore) find(id, userID string) (*domain.UserBooking, error) {
	for i := range f.listed {
		if b := f.listed[i].Booking; b.ID == id && b.UserID == userID {
			return &f.listed[i], nil
		}
	}
	return nil, repository.ErrBookingNotFound
}

func (f *fakeBookingStore) FindForUser(_ context.Context, id, userID string) (domain.UserBooking, error) {
	ub, err := f.find(id, userID)
	if err != nil {
		return domain.UserBooking{}, err
	}
	return *ub, nil
}

func (f *fakeBookingStore) Cancel(_ context.Context, id, userID, reason string, at time.Time) (domain.Booking, error) {
	ub, err := f.find(id, userID)
	if err != nil {
		return domain.Booking{}, err
	}
	b := &ub.Booking
	switch b.Status {
	case domain.RideStatusRequested, domain.RideStatusAccepted, domain.RideStatusArrived:
	default:
		return domain.Booking{}, repository.ErrBookingStateConflict
	}
	b.Status, b.CancelledAt, b.CancelledBy, b.CancelReason, b.StartOTP =
		domain.RideStatusCancelled, &at, domain.CancelledByCustomer, reason, ""
	return *b, nil
}

func (f *fakeBookingStore) RateDriver(_ context.Context, id, userID string, r domain.RideRating) error {
	ub, err := f.find(id, userID)
	if err != nil {
		return err
	}
	if ub.Booking.Status != domain.RideStatusCompleted || ub.Booking.DriverRating != nil {
		return repository.ErrBookingStateConflict
	}
	ub.Booking.DriverRating = &r
	return nil
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
	svc := NewBookingService(store, nil, nil)
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

// cancelAlerts records the bookings a BookingAlerter was told were cancelled.
type cancelAlerts struct{ cancelled []domain.Booking }

func (c *cancelAlerts) RideRequested(context.Context, domain.Booking, tripPlan) {}
func (c *cancelAlerts) RideCancelled(_ context.Context, b domain.Booking, _ tripPlan) {
	c.cancelled = append(c.cancelled, b)
}

// customerRide is u1's round trip from roundTripDetails, in status, with
// driverID assigned ("" for none).
func customerRide(id string, status domain.RideStatus, driverID string) domain.UserBooking {
	at := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC)
	ub := domain.UserBooking{Booking: domain.Booking{
		ID: id, UserID: "u1", TripType: TripRoundTrip, Details: roundTripDetails(),
		Status: status, ScheduledAt: &at, DriverID: driverID, StartOTP: "4821",
	}}
	if driverID != "" {
		ub.Driver = &domain.RideDriver{Name: "Ravi", PhoneE164: "+919800000001"}
	}
	return ub
}

func TestBookingService_Cancel(t *testing.T) {
	alerts := &cancelAlerts{}
	store := &fakeBookingStore{listed: []domain.UserBooking{
		customerRide("open", domain.RideStatusRequested, ""),
		customerRide("coming", domain.RideStatusAccepted, "d1"),
		customerRide("driving", domain.RideStatusInProgress, "d1"),
	}}
	svc := newTestBookingService(store)
	svc.alerts = alerts
	ctx := context.Background()

	// An open request: cancelled, nobody to tell.
	got, err := svc.Cancel(ctx, "u1", "open", "  Plans changed ")
	if err != nil {
		t.Fatalf("Cancel(open): %v", err)
	}
	if got.Status != domain.RideStatusCancelled || got.CancelReason != "Plans changed" ||
		got.CancelledBy != domain.CancelledByCustomer || got.CancelledAt == nil {
		t.Errorf("cancelled booking = %+v", got)
	}
	if len(alerts.cancelled) != 0 {
		t.Errorf("alerted %d drivers for an unassigned ride", len(alerts.cancelled))
	}

	// A ride a driver took: the driver is told, and the start code is gone.
	long := strings.Repeat("ड", 250) // over the cap, in multi-byte runes
	got, err = svc.Cancel(ctx, "u1", "coming", long)
	if err != nil {
		t.Fatalf("Cancel(coming): %v", err)
	}
	if got.StartOTP != "" {
		t.Errorf("start code still shown after cancelling: %q", got.StartOTP)
	}
	if n := utf8.RuneCountInString(got.CancelReason); n != maxCancelReason {
		t.Errorf("reason kept %d characters, want %d", n, maxCancelReason)
	}
	if len(alerts.cancelled) != 1 || alerts.cancelled[0].DriverID != "d1" {
		t.Errorf("alerts = %+v, want one for driver d1", alerts.cancelled)
	}

	// Underway, or someone else's: refused.
	if _, err := svc.Cancel(ctx, "u1", "driving", ""); !errors.Is(err, ErrCannotCancel) ||
		!errors.Is(err, repository.ErrBookingStateConflict) {
		t.Errorf("Cancel(driving) err = %v, want ErrCannotCancel", err)
	}
	if _, err := svc.Cancel(ctx, "u2", "open", ""); !errors.Is(err, repository.ErrBookingNotFound) {
		t.Errorf("Cancel(other user) err = %v, want ErrBookingNotFound", err)
	}
	if len(alerts.cancelled) != 1 {
		t.Errorf("refused cancels alerted drivers: %+v", alerts.cancelled)
	}
}

func TestBookingService_RateDriver(t *testing.T) {
	done := customerRide("done", domain.RideStatusCompleted, "d1")
	store := &fakeBookingStore{listed: []domain.UserBooking{
		done,
		customerRide("coming", domain.RideStatusAccepted, "d1"),
	}}
	svc := newTestBookingService(store)
	ctx := context.Background()

	for _, stars := range []int{0, 6, -1} {
		if _, err := svc.RateDriver(ctx, "u1", "done", stars, ""); !errors.Is(err, ErrInvalidRating) {
			t.Errorf("stars %d: err = %v, want ErrInvalidRating", stars, err)
		}
	}
	if _, err := svc.RateDriver(ctx, "u1", "done", 5, strings.Repeat("x", 501)); !errors.Is(err, ErrInvalidRating) {
		t.Errorf("long note: err = %v, want ErrInvalidRating", err)
	}

	got, err := svc.RateDriver(ctx, "u1", "done", 4, " Smooth driver ")
	if err != nil {
		t.Fatalf("RateDriver: %v", err)
	}
	if got.MyRating == nil || got.MyRating.Stars != 4 || got.MyRating.Note != "Smooth driver" {
		t.Errorf("myRating = %+v, want 4 stars with the trimmed note", got.MyRating)
	}

	// Once only, and only after the trip.
	if _, err := svc.RateDriver(ctx, "u1", "done", 5, ""); !errors.Is(err, ErrCannotRate) {
		t.Errorf("second rating: err = %v, want ErrCannotRate", err)
	}
	if _, err := svc.RateDriver(ctx, "u1", "coming", 5, ""); !errors.Is(err, ErrCannotRate) {
		t.Errorf("rating an upcoming ride: err = %v, want ErrCannotRate", err)
	}
}

func TestBookingService_ListMine_carriesTimelineAndRating(t *testing.T) {
	ub := customerRide("done", domain.RideStatusCompleted, "d1")
	accepted := time.Date(2026, 10, 24, 6, 0, 0, 0, time.UTC)
	ub.Booking.AcceptedAt = &accepted
	ub.Booking.DriverRating = &domain.RideRating{Stars: 5}
	ub.Booking.CustomerRating = &domain.RideRating{Stars: 2} // the driver's, not shown
	rating := 4.5
	ub.Driver.Rating, ub.Driver.RatingCount = &rating, 2
	svc := newTestBookingService(&fakeBookingStore{listed: []domain.UserBooking{ub}})

	got, err := svc.ListMine(context.Background(), "u1")
	if err != nil || len(got) != 1 {
		t.Fatalf("ListMine = %v, %v", got, err)
	}
	b := got[0]
	if b.AcceptedAt == nil || !b.AcceptedAt.Equal(accepted) || b.Hours != 4 {
		t.Errorf("timeline/trip = %+v", b)
	}
	if b.MyRating == nil || b.MyRating.Stars != 5 {
		t.Errorf("myRating = %+v, want the customer's own 5 stars", b.MyRating)
	}
	if b.Driver == nil || b.Driver.Rating == nil || *b.Driver.Rating != 4.5 || b.Driver.RatingCount != 2 {
		t.Errorf("driver = %+v, want rating 4.5 from 2", b.Driver)
	}
	if b.StartOTP != "" {
		t.Errorf("completed ride shows a start code: %q", b.StartOTP)
	}
}

func TestBookingService_DriverLocation(t *testing.T) {
	start := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC) // roundTripDetails
	live := memstore.NewLiveLocations()
	store := &fakeBookingStore{listed: []domain.UserBooking{
		customerRide("open", domain.RideStatusRequested, ""),
		customerRide("coming", domain.RideStatusAccepted, "d1"),
		customerRide("waiting", domain.RideStatusArrived, "d2"),
		customerRide("done", domain.RideStatusCompleted, "d1"),
	}}
	svc := newTestBookingService(store)
	svc.live = live
	ctx := context.Background()
	at := func(now time.Time) { svc.now = func() time.Time { return now } }

	// Two hours out, an accepted ride shares nothing yet.
	at(start.Add(-2 * time.Hour))
	if _, err := svc.DriverLocation(ctx, "u1", "coming"); !errors.Is(err, ErrNotTracking) {
		t.Errorf("2 h before: err = %v, want ErrNotTracking", err)
	}

	// From an hour before: in the window, but no fix shared yet.
	at(start.Add(-time.Hour))
	loc, err := svc.DriverLocation(ctx, "u1", "coming")
	if err != nil || loc != nil {
		t.Fatalf("1 h before, no fix: %+v, %v; want nil, nil", loc, err)
	}

	heading := 90.0
	live.Put("d1", domain.LiveLocation{Lat: 28.6, Lng: 77.2, Heading: &heading, UpdatedAt: start.Add(-time.Hour)})
	loc, err = svc.DriverLocation(ctx, "u1", "coming")
	if err != nil || loc == nil || loc.Lat != 28.6 || *loc.Heading != 90 {
		t.Fatalf("with a fix: %+v, %v", loc, err)
	}

	// A fix older than liveFixMaxAge is no fix.
	at(start.Add(-time.Hour + liveFixMaxAge + time.Second))
	if loc, err := svc.DriverLocation(ctx, "u1", "coming"); err != nil || loc != nil {
		t.Errorf("stale fix: %+v, %v; want nil, nil", loc, err)
	}

	// At the pickup the window is open whatever the clock says; a finished,
	// unassigned or someone else's ride never is.
	at(start.Add(-3 * time.Hour))
	if _, err := svc.DriverLocation(ctx, "u1", "waiting"); err != nil {
		t.Errorf("arrived: err = %v", err)
	}
	for _, id := range []string{"open", "done"} {
		if _, err := svc.DriverLocation(ctx, "u1", id); !errors.Is(err, ErrNotTracking) {
			t.Errorf("%s: err = %v, want ErrNotTracking", id, err)
		}
	}
	if _, err := svc.DriverLocation(ctx, "u2", "waiting"); !errors.Is(err, repository.ErrBookingNotFound) {
		t.Errorf("other user: err = %v, want ErrBookingNotFound", err)
	}
}
