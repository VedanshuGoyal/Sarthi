package service

import (
	"context"
	"slices"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// fakeWatchStore is an in-memory RideWatchStore.
type fakeWatchStore struct {
	mu       sync.Mutex
	bookings []domain.Booking
	events   map[string]bool // bookingID|kind
}

func newFakeWatchStore(bookings ...domain.Booking) *fakeWatchStore {
	return &fakeWatchStore{bookings: bookings, events: map[string]bool{}}
}

func (f *fakeWatchStore) Unmarked(_ context.Context, kind string, status domain.RideStatus, from, to time.Time, limit int) ([]domain.Booking, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []domain.Booking
	for _, b := range f.bookings {
		at := *b.ScheduledAt
		if b.Status == status && at.After(from) && !at.After(to) && !f.events[b.ID+"|"+kind] {
			out = append(out, b)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ScheduledAt.Before(*out[j].ScheduledAt) })
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

func (f *fakeWatchStore) Mark(_ context.Context, bookingID, kind string, _ time.Time) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	key := bookingID + "|" + kind
	if f.events[key] {
		return false, nil
	}
	f.events[key] = true
	return true, nil
}

func (f *fakeWatchStore) marked() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []string
	for k := range f.events {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// recordingWatchAlerts captures the watchdog's pushes as "kind bookingID".
type recordingWatchAlerts struct {
	mu   sync.Mutex
	sent []string
}

func (r *recordingWatchAlerts) add(kind string, b domain.Booking) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.sent = append(r.sent, kind+" "+b.ID)
}

func (r *recordingWatchAlerts) RealertDrivers(_ context.Context, b domain.Booking, _ tripPlan) {
	r.add("realert", b)
}
func (r *recordingWatchAlerts) NoDriverYet(_ context.Context, b domain.Booking, _ tripPlan) {
	r.add("no-driver-yet", b)
}
func (r *recordingWatchAlerts) NoDriverFound(_ context.Context, b domain.Booking, _ tripPlan) {
	r.add("no-driver", b)
}
func (r *recordingWatchAlerts) RideReminder(_ context.Context, b domain.Booking, _ tripPlan) {
	r.add("reminder", b)
}

func (r *recordingWatchAlerts) take() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := r.sent
	r.sent = nil
	sort.Strings(out)
	return out
}

// watchedRide is a round trip of hours, booked at created, starting at
// start, in status.
func watchedRide(id string, status domain.RideStatus, start, created time.Time, hours int) domain.Booking {
	b := openRide(id, start, hours, "automatic").Booking
	b.Status, b.CreatedAt, b.UserID = status, created, "u-"+id
	if status != domain.RideStatusRequested {
		b.DriverID = "auto"
	}
	return b
}

func newWatchTest(bookings ...domain.Booking) (*RideWatchdog, *fakeWatchStore, *recordingWatchAlerts, *time.Time) {
	store := newFakeWatchStore(bookings...)
	alerts := &recordingWatchAlerts{}
	w := NewRideWatchdog(store, alerts)
	now := testNow
	w.now = func() time.Time { return now }
	return w, store, alerts, &now
}

func TestWatchdog_unassignedRideIsRealertedThenReported(t *testing.T) {
	start := testNow.Add(4 * time.Hour)
	b := watchedRide("r1", domain.RideStatusRequested, start, testNow.Add(-24*time.Hour), 2)
	w, _, alerts, now := newWatchTest(b)
	ctx := context.Background()

	steps := []struct {
		at   time.Time
		want []string
	}{
		{start.Add(-4 * time.Hour), nil},
		{start.Add(-3 * time.Hour), []string{"realert r1"}},
		{start.Add(-3*time.Hour + time.Minute), nil}, // once
		{start.Add(-time.Hour), []string{"no-driver-yet r1", "realert r1"}},
		{start.Add(-45 * time.Minute), nil},
		{start.Add(-acceptCutoff), []string{"no-driver r1"}},
		{start.Add(time.Hour), nil},
	}
	for _, s := range steps {
		*now = s.at
		w.Tick(ctx)
		if got := alerts.take(); !slices.Equal(got, s.want) {
			t.Errorf("at T%+v: sent %q, want %q", s.at.Sub(start), got, s.want)
		}
	}
}

// A check missed while the server was down runs once it's back, while it's
// still worth anything — and only the latest re-alert, not both.
func TestWatchdog_catchesUpAfterDowntime(t *testing.T) {
	start := testNow.Add(4 * time.Hour)
	b := watchedRide("r1", domain.RideStatusRequested, start, testNow.Add(-24*time.Hour), 2)
	w, _, alerts, now := newWatchTest(b)

	*now = start.Add(-40 * time.Minute)
	w.Tick(context.Background())
	if got, want := alerts.take(), []string{"no-driver-yet r1", "realert r1"}; !slices.Equal(got, want) {
		t.Errorf("sent %q, want %q", got, want)
	}

	// Long after the ride: nothing left worth sending.
	late := watchedRide("r2", domain.RideStatusRequested, testNow.Add(-3*time.Hour), testNow.Add(-24*time.Hour), 2)
	w2, store2, alerts2, _ := newWatchTest(late)
	w2.Tick(context.Background())
	if got := alerts2.take(); len(got) != 0 || len(store2.marked()) != 0 {
		t.Errorf("a ride that closed hours ago: sent %q, marked %q", got, store2.marked())
	}
}

// A request that didn't exist an hour before its start was never "open an
// hour before", and one booked minutes ago was only just alerted.
func TestWatchdog_leavesNewRequestsAlone(t *testing.T) {
	start := testNow.Add(3 * time.Hour)
	fresh := watchedRide("fresh", domain.RideStatusRequested, start, start.Add(-3*time.Hour-10*time.Minute), 2)
	late := watchedRide("late", domain.RideStatusRequested, start, start.Add(-40*time.Minute), 2)
	w, _, alerts, now := newWatchTest(fresh, late)
	ctx := context.Background()

	*now = start.Add(-3 * time.Hour)
	w.Tick(ctx)
	if got := alerts.take(); len(got) != 0 {
		t.Errorf("at T-3h: sent %q, want nothing — fresh was alerted 10 minutes ago", got)
	}
	*now = start.Add(-35 * time.Minute)
	w.Tick(ctx)
	if got, want := alerts.take(), []string{"no-driver-yet fresh", "realert fresh"}; !slices.Equal(got, want) {
		t.Errorf("at T-35m: sent %q, want %q", got, want)
	}
	*now = start.Add(-acceptCutoff)
	w.Tick(ctx)
	if got, want := alerts.take(), []string{"no-driver fresh", "no-driver late"}; !slices.Equal(got, want) {
		t.Errorf("at close: sent %q, want %q", got, want)
	}
}

func TestWatchdog_remindsAnHourAheadAndWatchesForLateOrOverrunningRides(t *testing.T) {
	start := testNow.Add(2 * time.Hour)
	accepted := watchedRide("taken", domain.RideStatusAccepted, start, testNow.Add(-24*time.Hour), 2)
	acceptedAt := testNow.Add(-time.Hour)
	accepted.AcceptedAt = &acceptedAt
	justTaken := watchedRide("just", domain.RideStatusAccepted, start, testNow.Add(-24*time.Hour), 2)
	justAt := start.Add(-50 * time.Minute)
	justTaken.AcceptedAt = &justAt
	driving := watchedRide("driving", domain.RideStatusInProgress, start.Add(-6*time.Hour), testNow.Add(-24*time.Hour), 2)
	w, store, alerts, now := newWatchTest(accepted, justTaken, driving)
	ctx := context.Background()

	*now = start.Add(-time.Hour)
	w.Tick(ctx)
	if got, want := alerts.take(), []string{"reminder taken"}; !slices.Equal(got, want) {
		t.Errorf("at T-1h: sent %q, want %q (just was accepted after the hour mark)", got, want)
	}
	// "driving" began 5 h before T-1h for 2 h, so its end + 3 h is now: one
	// ops alert, no push.
	if got := store.marked(); !slices.Contains(got, "driving|"+eventRideOverrun) {
		t.Errorf("marked %q, want the overrunning ride", got)
	}

	*now = start.Add(15 * time.Minute)
	w.Tick(ctx)
	if got := store.marked(); !slices.Contains(got, "taken|"+eventLateArrival) ||
		!slices.Contains(got, "just|"+eventLateArrival) {
		t.Errorf("marked %q, want both late drivers reported", got)
	}
	if got := alerts.take(); len(got) != 0 {
		t.Errorf("ops checks pushed %q", got)
	}
	n := w.Tick(ctx)
	if n != 0 {
		t.Errorf("a second pass acted on %d bookings, want 0", n)
	}
}

func TestFormatUntil(t *testing.T) {
	for d, want := range map[time.Duration]string{
		-time.Minute:                    "now",
		59*time.Minute + 50*time.Second: "in 1 hour",
		45 * time.Minute:                "in 45 min",
		2 * time.Hour:                   "in 2 h",
		130 * time.Minute:               "in 2 h 10 min",
	} {
		if got := formatUntil(d); got != want {
			t.Errorf("formatUntil(%v) = %q, want %q", d, got, want)
		}
	}
}

func TestWatchdogPushes(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	_ = tokens.SaveForUser(context.Background(), "u1", "tok-phone")
	_ = tokens.SaveForDriver(context.Background(), "auto", "tok-auto")
	_ = tokens.SaveForDriver(context.Background(), "both", "tok-both")

	rb := openRide("ride-w", testNow.Add(time.Hour), 2, "automatic")
	rb.Booking.UserID, rb.Booking.DriverID = "u1", "auto"
	plan, _ := planOf(rb.Booking)

	svc.NoDriverYet(context.Background(), rb.Booking, plan)
	svc.Wait()
	m := sender.byToken()["tok-phone"]
	if m.Title != "Still finding your driver" || m.Data["type"] != pushTypeNoDriverYet ||
		!strings.Contains(m.Body, "until 9:30 AM") {
		t.Errorf("no driver yet = %+v", m)
	}

	svc.NoDriverFound(context.Background(), rb.Booking, plan)
	svc.Wait()
	if m := sender.byToken()["tok-phone"]; m.Title != "No driver found" || m.Data["type"] != pushTypeRideExpired {
		t.Errorf("no driver found = %+v", m)
	}

	sender.sent = nil
	svc.RideReminder(context.Background(), rb.Booking, plan)
	svc.Wait()
	got := sender.byToken()
	if len(got) != 2 || got["tok-both"].Token != "" {
		t.Fatalf("reminder sent to %v, want the ride's driver and customer", keys(got))
	}
	d, c := got["tok-auto"], got["tok-phone"]
	if d.Title != "Your ride starts in 1 hour" || d.Data["type"] != pushTypeRideReminder ||
		d.Channel != channelRideRequests || !strings.Contains(d.Body, "Pickup: India Gate") {
		t.Errorf("driver reminder = %+v", d)
	}
	if c.Channel != channelRideUpdates || !strings.Contains(c.Body, "at 10:00 AM") {
		t.Errorf("customer reminder = %+v", c)
	}
}
