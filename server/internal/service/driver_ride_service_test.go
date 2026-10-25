package service

import (
	"context"
	"errors"
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
	defer f.mu.Unlock()
	var out []domain.RideBooking
	for _, rb := range f.rides {
		if rb.Booking.DriverID == driverID {
			out = append(out, *rb)
		}
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
		"auto":    {KYCStatus: domain.KYCSubmitted, Transmission: domain.DriverTransmissionAutomatic},
		"both":    {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth},
		"pending": {KYCStatus: domain.KYCIncomplete, Transmission: domain.DriverTransmissionBoth},
	}, &fakePresence{online: map[string]bool{}}, memstore.NewOTPGuard())
	svc.now = func() time.Time { return testNow }
	codes := []string{"1111", "2222", "3333"}
	svc.newCode = func() (string, error) {
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
	if got[0].DistanceM == nil || *got[0].DistanceM > 5000 {
		t.Errorf("distance = %v, want a few km", got[0].DistanceM)
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

	var wins atomic.Int32
	var wg sync.WaitGroup
	for range 20 {
		wg.Go(func() {
			if _, err := svc.Accept(context.Background(), "both", "r1"); err == nil {
				wins.Add(1)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 1 {
		t.Errorf("winners = %d, want exactly 1", wins.Load())
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
	svc := NewDriverRideService(store, fakeProfiles{}, &fakePresence{online: map[string]bool{}}, memstore.NewOTPGuard())
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
	for i := range memstore.MaxOTPVerifyFailures - 1 {
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
	// The old code is dead; the new one works, with a fresh allowance.
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
