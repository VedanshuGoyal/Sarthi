package service

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/memstore"
	"github.com/sarthi/server/internal/repository"
)

// fakeRideStore is an in-memory DriverRideStore. Its Accept is atomic under
// the mutex, like the repository's conditional UPDATE.
type fakeRideStore struct {
	mu       sync.Mutex
	rides    map[string]*domain.RideBooking
	declined map[string]bool // rideID|driverID

	// afterList, when set, runs after ListForDriver has read — a seam to
	// widen the window between a check and the write that follows it.
	afterList func()
}

func newFakeRideStore(rides ...domain.RideBooking) *fakeRideStore {
	f := &fakeRideStore{rides: map[string]*domain.RideBooking{}, declined: map[string]bool{}}
	for i := range rides {
		rb := rides[i]
		f.rides[rb.Booking.ID] = &rb
	}
	return f
}

func (f *fakeRideStore) ListOpen(_ context.Context, driverID string, from time.Time, _ int) ([]domain.RideBooking, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []domain.RideBooking
	for id, rb := range f.rides {
		if rb.Booking.Status == domain.RideStatusRequested && !rb.Booking.ScheduledAt.Before(from) && !f.declined[id+"|"+driverID] {
			out = append(out, *rb)
		}
	}
	return out, nil
}

func (f *fakeRideStore) ListForDriver(_ context.Context, driverID string, _ int) ([]domain.RideBooking, error) {
	f.mu.Lock()
	var out []domain.RideBooking
	for _, rb := range f.rides {
		if rb.Booking.DriverID == driverID {
			out = append(out, *rb)
		}
	}
	hook := f.afterList
	f.mu.Unlock()
	if hook != nil {
		hook()
	}
	return out, nil
}

func (f *fakeRideStore) FindByID(_ context.Context, id string) (domain.RideBooking, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rb, ok := f.rides[id]
	if !ok {
		return domain.RideBooking{}, repository.ErrRideNotFound
	}
	return *rb, nil
}

func (f *fakeRideStore) SetStartOTP(_ context.Context, id, driverID, otp string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	rb, ok := f.rides[id]
	if !ok || rb.Booking.DriverID != driverID {
		return repository.ErrRideStateConflict
	}
	rb.Booking.StartOTP = otp
	return nil
}

func (f *fakeRideStore) Accept(_ context.Context, id, driverID string, at time.Time, otp string) (domain.RideBooking, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rb, ok := f.rides[id]
	if !ok || rb.Booking.Status != domain.RideStatusRequested {
		return domain.RideBooking{}, repository.ErrRideUnavailable
	}
	rb.Booking.Status = domain.RideStatusAccepted
	rb.Booking.DriverID = driverID
	rb.Booking.AcceptedAt = &at
	rb.Booking.StartOTP = otp
	return *rb, nil
}

func (f *fakeRideStore) Advance(_ context.Context, id, driverID string, from, to domain.RideStatus, at time.Time) (domain.RideBooking, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rb, ok := f.rides[id]
	if !ok || rb.Booking.DriverID != driverID || rb.Booking.Status != from {
		return domain.RideBooking{}, repository.ErrRideStateConflict
	}
	rb.Booking.Status = to
	return *rb, nil
}

func (f *fakeRideStore) Release(_ context.Context, id, driverID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	rb, ok := f.rides[id]
	if !ok || rb.Booking.DriverID != driverID ||
		(rb.Booking.Status != domain.RideStatusAccepted && rb.Booking.Status != domain.RideStatusArrived) {
		return repository.ErrRideStateConflict
	}
	rb.Booking.Status = domain.RideStatusRequested
	rb.Booking.DriverID = ""
	f.declined[id+"|"+driverID] = true
	return nil
}

func (f *fakeRideStore) Decline(_ context.Context, id, driverID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.declined[id+"|"+driverID] = true
	return nil
}

func (f *fakeRideStore) RateCustomer(_ context.Context, id, driverID string, r domain.RideRating) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	rb, ok := f.rides[id]
	if !ok || rb.Booking.DriverID != driverID || rb.Booking.Status != domain.RideStatusCompleted ||
		rb.Booking.CustomerRating != nil {
		return repository.ErrRideStateConflict
	}
	rb.Booking.CustomerRating = &r
	return nil
}

func (f *fakeRideStore) Earnings(context.Context, string, time.Time, time.Time, time.Time) (domain.DriverEarnings, error) {
	return domain.DriverEarnings{}, nil
}

type fakeProfiles map[string]domain.DriverProfile

func (f fakeProfiles) FindProfile(_ context.Context, id string) (domain.DriverProfile, error) {
	p, ok := f[id]
	if !ok {
		return domain.DriverProfile{}, repository.ErrDriverNotFound
	}
	return p, nil
}

type fakePresence struct{ online map[string]bool }

func (f *fakePresence) Register(d domain.Driver) { f.online[d.ID] = true }
func (f *fakePresence) UpdateLocation(string, domain.Location) error {
	return nil
}
func (f *fakePresence) Remove(id string) { delete(f.online, id) }

// testNow is the frozen clock the ride tests run at: 09:00 IST.
var testNow = time.Date(2026, 10, 25, 9, 0, 0, 0, ist)

// openRide is a round trip at India Gate starting at start for hours, in a
// car with the given gearbox.
func openRide(id string, start time.Time, hours int, gearbox string) domain.RideBooking {
	at := start
	return domain.RideBooking{
		Booking: domain.Booking{
			ID:       id,
			TripType: TripRoundTrip,
			Status:   domain.RideStatusRequested,
			Details: map[string]any{
				"pickup":      place("India Gate", 28.611, 77.2345),
				"hours":       float64(hours),
				"scheduledAt": start.Format(time.RFC3339),
				"car":         map[string]any{"registration": "DL01", "carType": "sedan", "transmission": gearbox},
				"fare":        240.0,
			},
			ScheduledAt: &at,
			FarePaise:   24000,
		},
		Customer: domain.RideCustomer{Name: "Asha", PhoneE164: "+919800000000"},
	}
}

func newRideService(store *fakeRideStore) *DriverRideService {
	svc := NewDriverRideService(store, fakeProfiles{
		"auto":    {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionAutomatic},
		"both":    {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth},
		"pending": {KYCStatus: domain.KYCIncomplete, Transmission: domain.DriverTransmissionBoth},
		"review":  {KYCStatus: domain.KYCSubmitted, Transmission: domain.DriverTransmissionBoth},
	}, &fakePresence{online: map[string]bool{}}, memstore.NewStartCodeGuard(), memstore.NewLiveLocations(), nil)
	svc.now = func() time.Time { return testNow }
	codes := []string{"1111", "2222", "3333"}
	var mu sync.Mutex // Accept runs in parallel in the race test
	svc.newCode = func() (string, error) {
		mu.Lock()
		defer mu.Unlock()
		c := codes[0]
		codes = append(codes[1:], c)
		return c, nil
	}
	return svc
}

// startWithCode starts a ride with the code it was issued — what the driver
// types after the customer reads it out.
func startWithCode(svc *DriverRideService, store *fakeRideStore) func(context.Context, string, string) (domain.DriverRide, error) {
	return func(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
		store.mu.Lock()
		code := store.rides[rideID].Booking.StartOTP
		store.mu.Unlock()
		return svc.Start(ctx, driverID, rideID, code)
	}
}

func TestRequests_filtersAndHidesCustomer(t *testing.T) {
	store := newFakeRideStore(
		openRide("auto-car", testNow.Add(2*time.Hour), 2, "automatic"),
		openRide("manual-car", testNow.Add(3*time.Hour), 2, "manual"),
		openRide("long-gone", testNow.Add(-2*time.Hour), 2, "automatic"),
	)
	svc := newRideService(store)

	got, err := svc.Requests(context.Background(), "auto", &LatLng{Lat: 28.6, Lng: 77.2})
	if err != nil {
		t.Fatalf("Requests: %v", err)
	}
	if len(got) != 1 || got[0].ID != "auto-car" {
		t.Fatalf("requests = %+v, want only auto-car", got)
	}
	if got[0].Customer != nil {
		t.Error("an open request must not reveal the customer")
	}
	// Roughly where, not exactly: the area, rounded coordinates, no plate —
	// but still the gearbox, so the driver can decide.
	if r := got[0]; !r.Approximate || r.Pickup.Lat != 28.61 || r.Pickup.Lng != 77.23 ||
		r.Car.Registration != "" || r.Car.Transmission != "automatic" {
		t.Errorf("request = %+v, want approximate", r)
	}
	if got[0].DistanceM == nil || *got[0].DistanceM > 5000 {
		t.Errorf("distance = %v, want a few km", got[0].DistanceM)
	}

	// Once taken, the driver gets everything.
	ride, err := svc.Accept(context.Background(), "auto", "auto-car")
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if ride.Approximate || ride.Pickup.Lat != 28.611 || ride.Car.Registration != "DL01" || ride.Customer == nil {
		t.Errorf("accepted ride = %+v, want the exact details", ride)
	}

	// Far away: outside the request radius.
	far, err := svc.Requests(context.Background(), "auto", &LatLng{Lat: 19.07, Lng: 72.87})
	if err != nil {
		t.Fatalf("Requests: %v", err)
	}
	if len(far) != 0 {
		t.Errorf("requests from Mumbai = %d, want 0", len(far))
	}
}

func TestRequests_closeHalfAnHourBeforeTheStart(t *testing.T) {
	store := newFakeRideStore(
		openRide("in-31m", testNow.Add(31*time.Minute), 2, "automatic"),
		openRide("in-29m", testNow.Add(29*time.Minute), 2, "automatic"),
	)
	svc := newRideService(store)
	ctx := context.Background()

	got, err := svc.Requests(ctx, "auto", nil)
	if err != nil {
		t.Fatalf("Requests: %v", err)
	}
	if len(got) != 1 || got[0].ID != "in-31m" {
		t.Fatalf("requests = %+v, want only in-31m", got)
	}

	// Accepting from a stale feed is refused the same way.
	if _, err := svc.Accept(ctx, "auto", "in-29m"); !errors.Is(err, ErrRideClosed) || !errors.Is(err, repository.ErrRideUnavailable) {
		t.Errorf("accept in-29m: err = %v, want ErrRideClosed (an ErrRideUnavailable)", err)
	}
	if _, err := svc.Accept(ctx, "auto", "in-31m"); err != nil {
		t.Errorf("accept in-31m: err = %v, want nil", err)
	}
}

func TestRequests_requiresClearedKYC(t *testing.T) {
	svc := newRideService(newFakeRideStore())
	if _, err := svc.Requests(context.Background(), "pending", nil); !errors.Is(err, ErrDriverNotCleared) {
		t.Errorf("err = %v, want ErrDriverNotCleared", err)
	}
	if err := svc.SetDuty(context.Background(), "pending", true, nil); !errors.Is(err, ErrDriverNotCleared) {
		t.Errorf("SetDuty err = %v, want ErrDriverNotCleared", err)
	}
	// Submitted means a person still has to look: not cleared yet.
	if err := svc.SetDuty(context.Background(), "review", true, nil); !errors.Is(err, ErrDriverNotCleared) {
		t.Errorf("SetDuty (under review) err = %v, want ErrDriverNotCleared", err)
	}
}

func TestAccept_lifecycle(t *testing.T) {
	store := newFakeRideStore(openRide("r1", testNow.Add(time.Hour), 2, "automatic"))
	svc := newRideService(store)
	ctx := context.Background()

	ride, err := svc.Accept(ctx, "auto", "r1")
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if ride.Status != domain.RideStatusAccepted || ride.Customer == nil || ride.Customer.Name != "Asha" {
		t.Fatalf("accepted ride = %+v, want accepted with customer", ride)
	}

	// Out of order: can't complete before starting.
	if _, err := svc.Complete(ctx, "auto", "r1"); !errors.Is(err, repository.ErrRideStateConflict) {
		t.Errorf("early complete err = %v, want ErrRideStateConflict", err)
	}
	for _, step := range []func(context.Context, string, string) (domain.DriverRide, error){
		svc.Arrive, startWithCode(svc, store), svc.Complete,
	} {
		if _, err := step(ctx, "auto", "r1"); err != nil {
			t.Fatalf("step: %v", err)
		}
	}
	if got := store.rides["r1"].Booking.Status; got != domain.RideStatusCompleted {
		t.Errorf("status = %s, want completed", got)
	}
	// Another driver can't touch it.
	if _, err := svc.Arrive(ctx, "both", "r1"); !errors.Is(err, repository.ErrRideStateConflict) {
		t.Errorf("other driver err = %v, want ErrRideStateConflict", err)
	}
}

func TestAccept_refusals(t *testing.T) {
	store := newFakeRideStore(
		openRide("manual", testNow.Add(time.Hour), 2, "manual"),
		openRide("first", testNow.Add(4*time.Hour), 2, "automatic"),
		// Starts 30 minutes after "first" ends — inside the gap.
		openRide("tight", testNow.Add(6*time.Hour+15*time.Minute), 1, "automatic"),
		openRide("later", testNow.Add(9*time.Hour), 1, "automatic"),
	)
	svc := newRideService(store)
	ctx := context.Background()

	if _, err := svc.Accept(ctx, "auto", "manual"); !errors.Is(err, ErrTransmissionMismatch) {
		t.Errorf("manual car err = %v, want ErrTransmissionMismatch", err)
	}
	if _, err := svc.Accept(ctx, "pending", "first"); !errors.Is(err, ErrDriverNotCleared) {
		t.Errorf("uncleared err = %v, want ErrDriverNotCleared", err)
	}
	if _, err := svc.Accept(ctx, "auto", "first"); err != nil {
		t.Fatalf("Accept first: %v", err)
	}
	if _, err := svc.Accept(ctx, "auto", "tight"); !errors.Is(err, ErrRideClash) {
		t.Errorf("tight err = %v, want ErrRideClash", err)
	}
	if _, err := svc.Accept(ctx, "auto", "later"); err != nil {
		t.Errorf("later: %v, want accepted", err)
	}
	if _, err := svc.Accept(ctx, "both", "first"); !errors.Is(err, repository.ErrRideUnavailable) {
		t.Errorf("taken err = %v, want ErrRideUnavailable", err)
	}
	if _, err := svc.Accept(ctx, "auto", "nope"); !errors.Is(err, repository.ErrRideNotFound) {
		t.Errorf("missing err = %v, want ErrRideNotFound", err)
	}
}

func TestAccept_raceHasOneWinner(t *testing.T) {
	store := newFakeRideStore(openRide("r1", testNow.Add(time.Hour), 2, "automatic"))
	svc := newRideService(store)
	profiles := fakeProfiles{}
	for i := range 20 {
		profiles[fmt.Sprint("d", i)] = domain.DriverProfile{KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth}
	}
	svc.profiles = profiles

	var winners sync.Map
	var wg sync.WaitGroup
	for i := range 20 {
		wg.Go(func() {
			if _, err := svc.Accept(context.Background(), fmt.Sprint("d", i), "r1"); err == nil {
				winners.Store(i, true)
			} else if !errors.Is(err, repository.ErrRideUnavailable) {
				t.Errorf("loser's err = %v, want ErrRideUnavailable", err)
			}
		})
	}
	wg.Wait()
	n := 0
	winners.Range(func(any, any) bool { n++; return true })
	if n != 1 {
		t.Errorf("winners = %d, want exactly 1", n)
	}
}

// A retried accept — the reply was lost, or the button fired twice — gets
// the ride the driver holds, not "you lost it". The customer hears once.
func TestAccept_isReplaySafe(t *testing.T) {
	ride := openRide("r1", testNow.Add(3*time.Hour), 2, "automatic")
	ride.Booking.UserID = "u1"
	store := newFakeRideStore(ride)
	svc := newRideService(store)
	alerts := &recordingAlerts{}
	svc.alerts = alerts
	ctx := context.Background()

	first, err := svc.Accept(ctx, "auto", "r1")
	if err != nil {
		t.Fatalf("Accept: %v", err)
	}
	again, err := svc.Accept(ctx, "auto", "r1")
	if err != nil {
		t.Fatalf("repeated Accept: %v, want the held ride", err)
	}
	if again.ID != "r1" || again.Status != domain.RideStatusAccepted || again.Customer == nil {
		t.Errorf("repeated accept = %+v, want the accepted ride with its customer", again)
	}
	if got := store.rides["r1"].Booking.StartOTP; got != "1111" {
		t.Errorf("start code = %q, want the first accept's 1111 kept", got)
	}
	if first.ID != again.ID || len(alerts.events) != 1 {
		t.Errorf("alerts = %v, want the customer told once", alerts.events)
	}
	// Someone else still can't have it.
	if _, err := svc.Accept(ctx, "both", "r1"); !errors.Is(err, repository.ErrRideUnavailable) {
		t.Errorf("another driver: err = %v, want ErrRideUnavailable", err)
	}

	// A double tap by one driver: both taps get the ride.
	store.rides["r2"] = ptr(openRide("r2", testNow.Add(8*time.Hour), 2, "automatic"))
	var wins atomic.Int32
	var wg sync.WaitGroup
	for range 5 {
		wg.Go(func() {
			if _, err := svc.Accept(ctx, "auto", "r2"); err == nil {
				wins.Add(1)
			} else {
				t.Errorf("double tap: err = %v", err)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 5 || store.rides["r2"].Booking.DriverID != "auto" {
		t.Errorf("double tap: %d of 5 got the ride", wins.Load())
	}
}

// Each step, asked for again once it's done, answers with the ride as it
// stands — and the customer isn't told twice.
func TestSteps_areReplaySafe(t *testing.T) {
	ride := openRide("r1", testNow.Add(time.Hour), 2, "automatic")
	ride.Booking.UserID = "u1"
	store := newFakeRideStore(ride)
	svc := newRideService(store)
	alerts := &recordingAlerts{}
	svc.alerts = alerts
	ctx := context.Background()
	if _, err := svc.Accept(ctx, "auto", "r1"); err != nil {
		t.Fatal(err)
	}

	for range 2 {
		if got, err := svc.Arrive(ctx, "auto", "r1"); err != nil || got.Status != domain.RideStatusArrived {
			t.Fatalf("Arrive = %v, %v", got.Status, err)
		}
	}
	code := store.rides["r1"].Booking.StartOTP
	if _, err := svc.Start(ctx, "auto", "r1", code); err != nil {
		t.Fatalf("Start: %v", err)
	}
	// The retry may carry any code: the ride is already underway.
	if got, err := svc.Start(ctx, "auto", "r1", ""); err != nil || got.Status != domain.RideStatusInProgress {
		t.Errorf("repeated Start = %v, %v; want in_progress", got.Status, err)
	}
	for range 2 {
		if got, err := svc.Complete(ctx, "auto", "r1"); err != nil || got.Status != domain.RideStatusCompleted {
			t.Fatalf("Complete = %v, %v", got.Status, err)
		}
	}
	want := []string{"assigned u1 r1", "arrived u1 auto r1", "completed u1 r1"}
	if strings.Join(alerts.events, "|") != strings.Join(want, "|") {
		t.Errorf("alerts = %q, want each once: %q", alerts.events, want)
	}

	// Going back a step is still refused, and so is another driver.
	if _, err := svc.Arrive(ctx, "auto", "r1"); !errors.Is(err, repository.ErrRideStateConflict) {
		t.Errorf("arrive after completing: err = %v, want ErrRideStateConflict", err)
	}
	if _, err := svc.Complete(ctx, "both", "r1"); !errors.Is(err, repository.ErrRideStateConflict) {
		t.Errorf("another driver completing: err = %v, want ErrRideStateConflict", err)
	}
}

// A double-fired accept on two overlapping rides must not win both: the
// clash check and the accept run one at a time per driver.
func TestAccept_sameDriverCantTakeTwoOverlappingRidesAtOnce(t *testing.T) {
	store := newFakeRideStore(
		openRide("r1", testNow.Add(time.Hour), 2, "automatic"),
		openRide("r2", testNow.Add(time.Hour+30*time.Minute), 2, "automatic"),
	)
	store.afterList = func() { time.Sleep(20 * time.Millisecond) }
	svc := newRideService(store)

	var wins atomic.Int32
	var wg sync.WaitGroup
	for _, id := range []string{"r1", "r2"} {
		wg.Go(func() {
			if _, err := svc.Accept(context.Background(), "both", id); err == nil {
				wins.Add(1)
			} else if !errors.Is(err, ErrRideClash) {
				t.Errorf("Accept %s: err = %v, want ErrRideClash for the loser", id, err)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 1 {
		t.Errorf("the driver won %d overlapping rides, want 1", wins.Load())
	}
}

func TestStart_oneRideAtATime(t *testing.T) {
	store := newFakeRideStore(
		openRide("a", testNow.Add(time.Hour), 1, "automatic"),
		openRide("b", testNow.Add(4*time.Hour), 1, "automatic"),
	)
	svc := newRideService(store)
	ctx := context.Background()
	for _, id := range []string{"a", "b"} {
		if _, err := svc.Accept(ctx, "auto", id); err != nil {
			t.Fatalf("Accept %s: %v", id, err)
		}
		if _, err := svc.Arrive(ctx, "auto", id); err != nil {
			t.Fatalf("Arrive %s: %v", id, err)
		}
	}
	start := startWithCode(svc, store)
	if _, err := start(ctx, "auto", "a"); err != nil {
		t.Fatalf("Start a: %v", err)
	}
	if _, err := start(ctx, "auto", "b"); !errors.Is(err, ErrRideInProgress) {
		t.Errorf("Start b err = %v, want ErrRideInProgress", err)
	}
}

func TestRelease_returnsRideToOthers(t *testing.T) {
	store := newFakeRideStore(openRide("r1", testNow.Add(time.Hour), 2, "automatic"))
	svc := newRideService(store)
	ctx := context.Background()

	if _, err := svc.Accept(ctx, "auto", "r1"); err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if err := svc.Release(ctx, "auto", "r1"); err != nil {
		t.Fatalf("Release: %v", err)
	}
	mine, _ := svc.Requests(ctx, "auto", nil)
	if len(mine) != 0 {
		t.Errorf("releasing driver still sees the ride")
	}
	theirs, _ := svc.Requests(ctx, "both", nil)
	if len(theirs) != 1 {
		t.Errorf("other driver sees %d rides, want 1", len(theirs))
	}
}

func TestEarnings_istWindows(t *testing.T) {
	var gotToday, gotWeek, gotMonth time.Time
	store := &earningsSpy{fakeRideStore: newFakeRideStore(), capture: func(today, week, month time.Time) {
		gotToday, gotWeek, gotMonth = today, week, month
	}}
	svc := NewDriverRideService(store, fakeProfiles{}, &fakePresence{online: map[string]bool{}}, memstore.NewStartCodeGuard(), memstore.NewLiveLocations(), nil)
	// Sunday 25 Oct 2026, 01:00 IST — still Saturday evening in UTC.
	svc.now = func() time.Time { return time.Date(2026, 10, 24, 19, 30, 0, 0, time.UTC) }

	if _, err := svc.Earnings(context.Background(), "auto"); err != nil {
		t.Fatalf("Earnings: %v", err)
	}
	if want := time.Date(2026, 10, 25, 0, 0, 0, 0, ist); !gotToday.Equal(want) {
		t.Errorf("today = %v, want %v", gotToday, want)
	}
	if want := time.Date(2026, 10, 19, 0, 0, 0, 0, ist); !gotWeek.Equal(want) {
		t.Errorf("week = %v, want Monday %v", gotWeek, want)
	}
	if want := time.Date(2026, 10, 1, 0, 0, 0, 0, ist); !gotMonth.Equal(want) {
		t.Errorf("month = %v, want %v", gotMonth, want)
	}
}

type earningsSpy struct {
	*fakeRideStore
	capture func(today, week, month time.Time)
}

func (s *earningsSpy) Earnings(_ context.Context, _ string, today, week, month time.Time) (domain.DriverEarnings, error) {
	s.capture(today, week, month)
	return domain.DriverEarnings{}, nil
}

func TestStart_requiresTheCustomersCode(t *testing.T) {
	store := newFakeRideStore(openRide("r1", testNow.Add(time.Hour), 2, "automatic"))
	svc := newRideService(store)
	ctx := context.Background()

	if _, err := svc.Accept(ctx, "auto", "r1"); err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if got := store.rides["r1"].Booking.StartOTP; got != "1111" {
		t.Fatalf("issued code = %q, want 1111", got)
	}
	// Not at the pickup yet: the code alone doesn't start it.
	if _, err := svc.Start(ctx, "auto", "r1", "1111"); !errors.Is(err, repository.ErrRideStateConflict) {
		t.Errorf("start before arrive err = %v, want ErrRideStateConflict", err)
	}
	if _, err := svc.Arrive(ctx, "auto", "r1"); err != nil {
		t.Fatalf("Arrive: %v", err)
	}

	// Four wrong codes are just wrong; the fifth replaces the code.
	for i := range memstore.MaxStartCodeFailures - 1 {
		if _, err := svc.Start(ctx, "auto", "r1", "9999"); !errors.Is(err, ErrStartOTPIncorrect) {
			t.Fatalf("wrong code %d err = %v, want ErrStartOTPIncorrect", i+1, err)
		}
	}
	if _, err := svc.Start(ctx, "auto", "r1", "9999"); !errors.Is(err, ErrStartOTPReset) {
		t.Fatalf("last wrong code err = %v, want ErrStartOTPReset", err)
	}
	if got := store.rides["r1"].Booking.StartOTP; got != "2222" {
		t.Fatalf("code after reset = %q, want 2222", got)
	}
	// The old code is dead; the new one works.
	if _, err := svc.Start(ctx, "auto", "r1", "1111"); !errors.Is(err, ErrStartOTPIncorrect) {
		t.Errorf("old code err = %v, want ErrStartOTPIncorrect", err)
	}
	ride, err := svc.Start(ctx, "auto", "r1", "2222")
	if err != nil {
		t.Fatalf("Start with new code: %v", err)
	}
	if ride.Status != domain.RideStatusInProgress {
		t.Errorf("status = %s, want in_progress", ride.Status)
	}
}

// Guessing can't be scripted: once a ride's codes keep being used up, it
// refuses every code — even the right one — for a while.
func TestStart_locksARideAfterRepeatedWrongCodes(t *testing.T) {
	store := newFakeRideStore(openRide("r1", testNow.Add(time.Hour), 2, "automatic"))
	svc := newRideService(store)
	ctx := context.Background()
	if _, err := svc.Accept(ctx, "auto", "r1"); err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if _, err := svc.Arrive(ctx, "auto", "r1"); err != nil {
		t.Fatalf("Arrive: %v", err)
	}

	misses := memstore.MaxStartCodeFailures * memstore.MaxStartCodeResets
	var err error
	for range misses {
		_, err = svc.Start(ctx, "auto", "r1", "0000")
	}
	if !errors.Is(err, ErrStartLocked) {
		t.Fatalf("after %d wrong codes err = %v, want ErrStartLocked", misses, err)
	}
	if locked, ok := errors.AsType[*StartLockedError](err); !ok || locked.RetryAfter != memstore.StartCodeLockDuration {
		t.Errorf("lock = %+v, want %v", locked, memstore.StartCodeLockDuration)
	}
	right := store.rides["r1"].Booking.StartOTP
	if _, err := svc.Start(ctx, "auto", "r1", right); !errors.Is(err, ErrStartLocked) {
		t.Errorf("right code while locked: err = %v, want ErrStartLocked", err)
	}
	if store.rides["r1"].Booking.Status != domain.RideStatusArrived {
		t.Errorf("status = %s, want still arrived", store.rides["r1"].Booking.Status)
	}
}

// A driver taken off the road gives back the rides they haven't started;
// one underway is left to finish.
func TestReleaseHeldRides(t *testing.T) {
	ride := func(id string, status domain.RideStatus) domain.RideBooking {
		rb := openRide(id, testNow.Add(3*time.Hour), 1, "automatic")
		rb.Booking.Status, rb.Booking.DriverID, rb.Booking.UserID = status, "auto", "u-"+id
		return rb
	}
	store := newFakeRideStore(
		ride("accepted", domain.RideStatusAccepted),
		ride("arrived", domain.RideStatusArrived),
		ride("driving", domain.RideStatusInProgress),
		ride("done", domain.RideStatusCompleted),
	)
	svc := newRideService(store)
	alerts := &recordingAlerts{}
	svc.alerts = alerts

	n, err := svc.ReleaseHeldRides(context.Background(), "auto")
	if err != nil || n != 2 {
		t.Fatalf("ReleaseHeldRides = %d, %v; want 2", n, err)
	}
	for id, want := range map[string]domain.RideStatus{
		"accepted": domain.RideStatusRequested, "arrived": domain.RideStatusRequested,
		"driving": domain.RideStatusInProgress, "done": domain.RideStatusCompleted,
	} {
		if got := store.rides[id].Booking.Status; got != want {
			t.Errorf("%s: status %s, want %s", id, got, want)
		}
	}
	if len(alerts.events) != 2 {
		t.Errorf("alerts = %v, want the two customers told", alerts.events)
	}
}

func TestClearance_needsALicenceInDate(t *testing.T) {
	expired := fakeProfiles{"auto": {
		KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionAutomatic,
		LicenseValidUntil: &domain.Date{Time: time.Date(2026, 10, 24, 0, 0, 0, 0, time.UTC)},
	}}
	svc := newRideService(newFakeRideStore(openRide("r1", testNow.Add(3*time.Hour), 1, "automatic")))
	svc.profiles = expired
	if _, err := svc.Requests(context.Background(), "auto", nil); !errors.Is(err, ErrDriverNotCleared) {
		t.Errorf("licence expired yesterday: err = %v, want ErrDriverNotCleared", err)
	}
	// Valid through today (25 Oct, IST) still drives.
	p := expired["auto"]
	p.LicenseValidUntil = &domain.Date{Time: time.Date(2026, 10, 25, 0, 0, 0, 0, time.UTC)}
	svc.profiles = fakeProfiles{"auto": p}
	if _, err := svc.Requests(context.Background(), "auto", nil); err != nil {
		t.Errorf("licence valid today: err = %v", err)
	}
}

func TestNewStartOTP_isFourDigits(t *testing.T) {
	for range 200 {
		code, err := newStartOTP()
		if err != nil {
			t.Fatalf("newStartOTP: %v", err)
		}
		if len(code) != 4 || strings.Trim(code, "0123456789") != "" {
			t.Fatalf("code = %q, want 4 digits", code)
		}
	}
}

// recordingAlerts captures the ride alerts DriverRideService raises.
type recordingAlerts struct {
	mu     sync.Mutex
	events []string
}

func (r *recordingAlerts) add(e string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, e)
}

func (r *recordingAlerts) DriverAssigned(_ context.Context, userID string, ride domain.DriverRide, _ string) {
	r.add("assigned " + userID + " " + ride.ID)
}

func (r *recordingAlerts) DriverArrived(_ context.Context, userID, driverID string, ride domain.DriverRide) {
	r.add("arrived " + userID + " " + driverID + " " + ride.ID)
}

func (r *recordingAlerts) DriverReleased(_ context.Context, b domain.Booking, _ tripPlan, driverID string) {
	r.add("released " + b.UserID + " " + driverID + " " + b.ID)
}

func (r *recordingAlerts) RideCompleted(_ context.Context, userID string, ride domain.DriverRide) {
	r.add("completed " + userID + " " + ride.ID)
}

func TestRideAlerts_acceptArriveRelease(t *testing.T) {
	ride := openRide("r1", testNow.Add(3*time.Hour), 2, "automatic")
	ride.Booking.UserID = "u1"
	store := newFakeRideStore(ride)
	svc := newRideService(store)
	alerts := &recordingAlerts{}
	svc.alerts = alerts
	ctx := context.Background()

	if _, err := svc.Accept(ctx, "auto", "r1"); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Arrive(ctx, "auto", "r1"); err != nil {
		t.Fatal(err)
	}
	if err := svc.Release(ctx, "auto", "r1"); err != nil {
		t.Fatal(err)
	}
	// A failed release (no longer theirs) raises nothing.
	if err := svc.Release(ctx, "auto", "r1"); err == nil {
		t.Fatal("second release should fail")
	}

	want := []string{"assigned u1 r1", "arrived u1 auto r1", "released u1 auto r1"}
	if strings.Join(alerts.events, "|") != strings.Join(want, "|") {
		t.Errorf("alerts = %q, want %q", alerts.events, want)
	}
}

func TestRateCustomer(t *testing.T) {
	done := openRide("done", testNow.Add(-6*time.Hour), 2, "automatic")
	done.Booking.Status, done.Booking.DriverID = domain.RideStatusCompleted, "auto"
	coming := openRide("coming", testNow.Add(6*time.Hour), 2, "automatic")
	coming.Booking.Status, coming.Booking.DriverID = domain.RideStatusAccepted, "auto"
	store := newFakeRideStore(done, coming)
	svc := newRideService(store)
	ctx := context.Background()

	if _, err := svc.RateCustomer(ctx, "auto", "done", 9, ""); !errors.Is(err, ErrInvalidRating) {
		t.Errorf("9 stars: err = %v, want ErrInvalidRating", err)
	}
	ride, err := svc.RateCustomer(ctx, "auto", "done", 3, "Kept me waiting")
	if err != nil {
		t.Fatalf("RateCustomer: %v", err)
	}
	if ride.MyRating == nil || ride.MyRating.Stars != 3 || ride.Customer == nil {
		t.Errorf("ride = %+v, want myRating 3 and the customer", ride)
	}
	for _, tc := range []struct{ driver, ride string }{
		{"auto", "done"},   // twice
		{"auto", "coming"}, // not finished
		{"both", "done"},   // not theirs
	} {
		if _, err := svc.RateCustomer(ctx, tc.driver, tc.ride, 5, ""); !errors.Is(err, ErrCannotRateRide) ||
			!errors.Is(err, repository.ErrRideStateConflict) {
			t.Errorf("%s rating %s: err = %v, want ErrCannotRateRide", tc.driver, tc.ride, err)
		}
	}
}

func TestCustomerCancelledRide_isGoneForDrivers(t *testing.T) {
	gone := openRide("gone", testNow.Add(5*time.Hour), 2, "automatic")
	gone.Booking.Status = domain.RideStatusCancelled
	cancelledAt := testNow.Add(-time.Minute)
	held := openRide("held", testNow.Add(8*time.Hour), 2, "automatic")
	held.Booking.Status, held.Booking.DriverID = domain.RideStatusCancelled, "auto"
	held.Booking.CancelledAt, held.Booking.CancelledBy, held.Booking.CancelReason =
		&cancelledAt, domain.CancelledByCustomer, "Plans changed"
	store := newFakeRideStore(gone, held)
	svc := newRideService(store)
	ctx := context.Background()

	if feed, _ := svc.Requests(ctx, "auto", nil); len(feed) != 0 {
		t.Errorf("feed = %d rides, want none", len(feed))
	}
	if _, err := svc.Accept(ctx, "auto", "gone"); !errors.Is(err, repository.ErrRideUnavailable) {
		t.Errorf("accepting a cancelled ride: err = %v, want ErrRideUnavailable", err)
	}

	// The driver who had it sees it cancelled, with why — and it doesn't
	// block the hours it held.
	mine, _ := svc.MyRides(ctx, "auto")
	if len(mine) != 1 || mine[0].Status != domain.RideStatusCancelled ||
		mine[0].CancelReason != "Plans changed" || mine[0].CancelledBy != domain.CancelledByCustomer {
		t.Fatalf("my rides = %+v", mine)
	}
	store.rides["clash"] = ptr(openRide("clash", testNow.Add(8*time.Hour), 2, "automatic"))
	if _, err := svc.Accept(ctx, "auto", "clash"); err != nil {
		t.Errorf("accepting over a cancelled ride's hours: %v", err)
	}
}

func TestShareLocation(t *testing.T) {
	store := newFakeRideStore()
	live := memstore.NewLiveLocations()
	svc := newRideService(store)
	svc.live = live
	ctx := context.Background()

	for _, bad := range [][2]float64{{91, 0}, {0, 181}, {-90.5, 10}, {math.NaN(), 0}} {
		if err := svc.ShareLocation(ctx, "auto", bad[0], bad[1], nil); !errors.Is(err, ErrInvalidLocation) {
			t.Errorf("%v: err = %v, want ErrInvalidLocation", bad, err)
		}
	}
	heading := -90.0
	if err := svc.ShareLocation(ctx, "auto", 28.6, 77.2, &heading); err != nil {
		t.Fatalf("ShareLocation: %v", err)
	}
	got, ok := live.Latest("auto")
	if !ok || got.Lat != 28.6 || got.Heading == nil || *got.Heading != 270 || !got.UpdatedAt.Equal(testNow) {
		t.Errorf("stored %+v, %v; want the fix at testNow, heading 270", got, ok)
	}
}
