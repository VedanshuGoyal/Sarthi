package service

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/memstore"
	"github.com/sarthi/server/internal/push"
)

// fakeTokens is an in-memory PushTokenStore.
type fakeTokens struct {
	mu      sync.Mutex
	users   map[string][]string
	drivers map[string][]string
	deleted []string
}

func (f *fakeTokens) SaveForUser(_ context.Context, userID, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.users[userID] = append(f.users[userID], token)
	return nil
}

func (f *fakeTokens) SaveForDriver(_ context.Context, driverID, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.drivers[driverID] = append(f.drivers[driverID], token)
	return nil
}

func (f *fakeTokens) DeleteForUser(context.Context, string, string) error   { return nil }
func (f *fakeTokens) DeleteForDriver(context.Context, string, string) error { return nil }

func (f *fakeTokens) Delete(_ context.Context, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.deleted = append(f.deleted, token)
	return nil
}

func (f *fakeTokens) ForUser(_ context.Context, userID string) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.users[userID], nil
}

func (f *fakeTokens) ForDrivers(_ context.Context, ids []string) (map[string][]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := map[string][]string{}
	for _, id := range ids {
		if t := f.drivers[id]; len(t) > 0 {
			out[id] = t
		}
	}
	return out, nil
}

// fakeSender records messages; tokens in gone answer ErrUnregistered.
type fakeSender struct {
	mu   sync.Mutex
	sent []push.Message
	gone map[string]bool
}

func (f *fakeSender) Send(_ context.Context, m push.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.gone[m.Token] {
		return push.ErrUnregistered
	}
	f.sent = append(f.sent, m)
	return nil
}

func (f *fakeSender) byToken() map[string]push.Message {
	out := map[string]push.Message{}
	for _, m := range f.sent {
		out[m.Token] = m
	}
	return out
}

// openRide's pickup at India Gate.
const (
	gateLat, gateLng = 28.611, 77.2345 // openRide's pickup
)

func newNotifyTest(t *testing.T) (*NotifyService, *fakeTokens, *fakeSender, *memstore.DriverTracker) {
	t.Helper()
	tokens := &fakeTokens{users: map[string][]string{}, drivers: map[string][]string{}}
	sender := &fakeSender{gone: map[string]bool{}}
	tracker := memstore.NewDriverTracker(7)
	profiles := fakeProfiles{
		"auto":    {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionAutomatic},
		"manual":  {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionManual},
		"both":    {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth},
		"far":     {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth},
		"stale":   {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth},
		"pending": {KYCStatus: domain.KYCIncomplete, Transmission: domain.DriverTransmissionBoth},
	}
	svc := NewNotifyService(tokens, sender, tracker, profiles)
	svc.now = func() time.Time { return testNow }
	return svc, tokens, sender, tracker
}

func placeDriver(t *testing.T, tr *memstore.DriverTracker, id string, lat, lng float64, seen time.Time) {
	t.Helper()
	if err := tr.UpdateLocation(id, domain.Location{Lat: lat, Lng: lng, UpdatedAt: seen}); err != nil {
		t.Fatal(err)
	}
}

func TestRideRequested_alertsEligibleNearbyDrivers(t *testing.T) {
	svc, tokens, sender, tr := newNotifyTest(t)
	fresh := testNow.Add(-time.Minute)
	placeDriver(t, tr, "auto", gateLat+0.018, gateLng, fresh) // ~2 km
	placeDriver(t, tr, "both", gateLat, gateLng+0.005, fresh)
	placeDriver(t, tr, "manual", gateLat, gateLng, fresh)                  // wrong gearbox
	placeDriver(t, tr, "pending", gateLat, gateLng, fresh)                 // KYC not done
	placeDriver(t, tr, "stale", gateLat, gateLng, testNow.Add(-time.Hour)) // app closed
	placeDriver(t, tr, "far", gateLat+0.72, gateLng, fresh)                // ~80 km
	for _, id := range []string{"auto", "both", "manual", "pending", "stale", "far"} {
		_ = tokens.SaveForDriver(context.Background(), id, "tok-"+id)
	}
	_ = tokens.SaveForDriver(context.Background(), "both", "tok-both-2")
	sender.gone["tok-both-2"] = true

	rb := openRide("ride-1", testNow.Add(3*time.Hour), 4, "automatic")
	plan, _ := parseTripPlan(rb.Booking.TripType, rb.Booking.Details)
	plan.ScheduledAt = *rb.Booking.ScheduledAt
	svc.RideRequested(context.Background(), rb.Booking, plan)
	svc.Wait()

	got := sender.byToken()
	if len(got) != 2 || got["tok-auto"].Token == "" || got["tok-both"].Token == "" {
		t.Fatalf("alerted %v, want tok-auto and tok-both", keys(got))
	}
	m := got["tok-auto"]
	if m.Channel != channelRideRequests || m.Data["type"] != pushTypeRideRequest || m.Data["rideId"] != "ride-1" {
		t.Errorf("message routing = %+v", m)
	}
	if !strings.HasPrefix(m.Title, "New ride request · ₹") {
		t.Errorf("title = %q", m.Title)
	}
	if !strings.Contains(m.Body, "Round trip, 4 h") || !strings.Contains(m.Body, "2.0 km away") ||
		!strings.Contains(m.Body, "12:00 PM") {
		t.Errorf("body = %q", m.Body)
	}
	// Worth delivering only until the ride closes to drivers.
	if want := 3*time.Hour - acceptCutoff; m.TTL != want {
		t.Errorf("TTL = %v, want %v", m.TTL, want)
	}
	if len(tokens.deleted) != 1 || tokens.deleted[0] != "tok-both-2" {
		t.Errorf("deleted = %v, want the unregistered tok-both-2", tokens.deleted)
	}
}

func TestRideRequested_skipsClosedRides(t *testing.T) {
	svc, tokens, sender, tr := newNotifyTest(t)
	placeDriver(t, tr, "both", gateLat, gateLng, testNow)
	_ = tokens.SaveForDriver(context.Background(), "both", "tok-both")

	rb := openRide("ride-2", testNow.Add(20*time.Minute), 2, "")
	plan, _ := parseTripPlan(rb.Booking.TripType, rb.Booking.Details)
	plan.ScheduledAt = *rb.Booking.ScheduledAt
	svc.RideRequested(context.Background(), rb.Booking, plan)
	svc.Wait()
	if len(sender.sent) != 0 {
		t.Fatalf("sent %d alerts for a ride already closed to drivers", len(sender.sent))
	}
}

func TestDriverAssigned_tellsTheCustomer(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	_ = tokens.SaveForUser(context.Background(), "u1", "tok-phone")
	_ = tokens.SaveForUser(context.Background(), "u1", "tok-tablet")
	_ = tokens.SaveForUser(context.Background(), "u2", "tok-other")

	ride := domain.DriverRide{
		ID:          "ride-3",
		ScheduledAt: time.Date(2026, 10, 26, 10, 30, 0, 0, ist),
		Pickup:      domain.RidePlace{Address: "India Gate, New Delhi"},
	}
	svc.DriverAssigned(context.Background(), "u1", ride, " Ramesh Kumar ")
	svc.Wait()

	got := sender.byToken()
	if len(got) != 2 || got["tok-other"].Token != "" {
		t.Fatalf("sent to %v, want u1's two devices", keys(got))
	}
	m := got["tok-phone"]
	if m.Title != "Driver assigned" || m.Channel != channelRideUpdates || m.Data["type"] != pushTypeDriverAssigned {
		t.Errorf("message = %+v", m)
	}
	want := "Ramesh Kumar is your driver for Mon 26 Oct, 10:30 AM.\nPickup: India Gate, New Delhi"
	if m.Body != want {
		t.Errorf("body = %q, want %q", m.Body, want)
	}
}

func TestNotify_withoutSenderSendsNothingButKeepsTokens(t *testing.T) {
	tokens := &fakeTokens{users: map[string][]string{}, drivers: map[string][]string{}}
	svc := NewNotifyService(tokens, nil, memstore.NewDriverTracker(7), fakeProfiles{})
	if err := svc.RegisterUserDevice(context.Background(), "u1", " tok "); err != nil {
		t.Fatal(err)
	}
	if got := tokens.users["u1"]; len(got) != 1 || got[0] != "tok" {
		t.Errorf("stored %v, want trimmed tok", got)
	}
	svc.DriverAssigned(context.Background(), "u1", domain.DriverRide{ID: "r"}, "X")
	svc.Wait() // must not hang or panic with no sender
}

func TestRegisterDevice_rejectsBlankTokens(t *testing.T) {
	svc, _, _, _ := newNotifyTest(t)
	for _, tok := range []string{"", "   ", strings.Repeat("x", maxPushTokenLen+1)} {
		if err := svc.RegisterDriverDevice(context.Background(), "d1", tok); !errors.Is(err, ErrInvalidPushToken) {
			t.Errorf("RegisterDriverDevice(%d chars) err = %v", len(tok), err)
		}
	}
}

func TestFormatFare(t *testing.T) {
	cases := map[int64]string{
		0:         "₹0",
		44000:     "₹440",
		123400:    "₹1,234",
		12345600:  "₹1,23,456",
		123456700: "₹12,34,567",
	}
	for paise, want := range cases {
		if got := formatFare(paise, false); got != want {
			t.Errorf("formatFare(%d) = %q, want %q", paise, got, want)
		}
	}
	if got := formatFare(64000, true); got != "~₹640" {
		t.Errorf("estimated = %q", got)
	}
}

func keys(m map[string]push.Message) []string {
	var out []string
	for k := range m {
		out = append(out, k)
	}
	return out
}

func TestDriverArrived_tellsTheCustomer(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	_ = tokens.SaveForUser(context.Background(), "u1", "tok-phone")

	svc.DriverArrived(context.Background(), "u1", "missing-driver", domain.DriverRide{
		ID: "ride-4", Pickup: domain.RidePlace{Address: "India Gate"},
	})
	svc.Wait()

	m := sender.byToken()["tok-phone"]
	if m.Title != "Your driver has arrived" || m.Data["type"] != pushTypeDriverArrived || m.Channel != channelRideUpdates {
		t.Fatalf("message = %+v", m)
	}
	// No KYC name on file → a generic subject, and never the start code.
	want := "Your driver is at the pickup. Share the start code from the app to begin.\nPickup: India Gate"
	if m.Body != want {
		t.Errorf("body = %q, want %q", m.Body, want)
	}
}

func TestDriverReleased_tellsCustomerAndRealertsOthers(t *testing.T) {
	svc, tokens, sender, tr := newNotifyTest(t)
	fresh := testNow.Add(-time.Minute)
	placeDriver(t, tr, "auto", gateLat, gateLng, fresh) // dropped the ride
	placeDriver(t, tr, "both", gateLat, gateLng, fresh)
	_ = tokens.SaveForDriver(context.Background(), "auto", "tok-auto")
	_ = tokens.SaveForDriver(context.Background(), "both", "tok-both")
	_ = tokens.SaveForUser(context.Background(), "u1", "tok-phone")

	rb := openRide("ride-5", testNow.Add(3*time.Hour), 4, "automatic")
	rb.Booking.UserID = "u1"
	plan, _ := parseTripPlan(rb.Booking.TripType, rb.Booking.Details)
	plan.ScheduledAt = *rb.Booking.ScheduledAt
	svc.DriverReleased(context.Background(), rb.Booking, plan, "auto")
	svc.Wait()

	got := sender.byToken()
	if len(got) != 2 || got["tok-auto"].Token != "" {
		t.Fatalf("sent to %v, want the customer and the other driver", keys(got))
	}
	c := got["tok-phone"]
	if c.Title != "Your driver cancelled" || c.Data["type"] != pushTypeDriverReleased ||
		!strings.Contains(c.Body, "We're finding you another driver.") {
		t.Errorf("customer message = %+v", c)
	}
	if d := got["tok-both"]; d.Data["type"] != pushTypeRideRequest || d.Data["rideId"] != "ride-5" {
		t.Errorf("driver message = %+v", d)
	}
}

func TestDriverReleased_tooLateToRebook(t *testing.T) {
	svc, tokens, sender, tr := newNotifyTest(t)
	placeDriver(t, tr, "both", gateLat, gateLng, testNow)
	_ = tokens.SaveForDriver(context.Background(), "both", "tok-both")
	_ = tokens.SaveForUser(context.Background(), "u1", "tok-phone")

	rb := openRide("ride-6", testNow.Add(20*time.Minute), 2, "")
	rb.Booking.UserID = "u1"
	plan, _ := parseTripPlan(rb.Booking.TripType, rb.Booking.Details)
	plan.ScheduledAt = *rb.Booking.ScheduledAt
	svc.DriverReleased(context.Background(), rb.Booking, plan, "auto")
	svc.Wait()

	got := sender.byToken()
	if len(got) != 1 || !strings.HasSuffix(got["tok-phone"].Body, "Please book again.") {
		t.Fatalf("sent %v (customer body %q), want only the customer, told to book again",
			keys(got), got["tok-phone"].Body)
	}
}

func TestRideCancelled_tellsTheDriver(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	_ = tokens.SaveForDriver(context.Background(), "auto", "tok-auto")
	_ = tokens.SaveForDriver(context.Background(), "both", "tok-both")

	rb := openRide("ride-7", testNow.Add(3*time.Hour), 4, "automatic")
	rb.Booking.DriverID, rb.Booking.CancelReason = "auto", "Plans changed"
	plan, _ := parseTripPlan(rb.Booking.TripType, rb.Booking.Details)
	plan.ScheduledAt = *rb.Booking.ScheduledAt
	svc.RideCancelled(context.Background(), rb.Booking, plan)
	svc.Wait()

	got := sender.byToken()
	if len(got) != 1 {
		t.Fatalf("sent to %v, want only the driver who had the ride", keys(got))
	}
	m := got["tok-auto"]
	if m.Title != "Ride cancelled" || m.Channel != channelRideRequests ||
		m.Data["type"] != pushTypeRideCancelled || m.Data["rideId"] != "ride-7" {
		t.Errorf("message = %+v", m)
	}
	want := "The customer cancelled their ride on Sun 25 Oct, 12:00 PM (Round trip, 4 h).\nReason: Plans changed"
	if m.Body != want {
		t.Errorf("body = %q, want %q", m.Body, want)
	}

	// No driver yet: nobody to tell.
	rb.Booking.DriverID = ""
	svc.RideCancelled(context.Background(), rb.Booking, plan)
	svc.Wait()
	if n := len(sender.byToken()); n != 1 {
		t.Errorf("sent %d messages after an unassigned cancel, want still 1", n)
	}
}
