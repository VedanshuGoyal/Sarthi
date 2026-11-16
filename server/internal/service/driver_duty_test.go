package service

import (
	"context"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/memstore"
	"github.com/sarthi/server/pkg/geo"
)

// fakeDuty is an in-memory DutyStore, DutyLister and DutyExpirer.
type fakeDuty struct {
	mu    sync.Mutex
	rows  map[string]domain.DriverDuty // on duty only
	saves int
}

func newFakeDuty(rows ...domain.DriverDuty) *fakeDuty {
	f := &fakeDuty{rows: map[string]domain.DriverDuty{}}
	for _, r := range rows {
		f.rows[r.DriverID] = r
	}
	return f
}

func (f *fakeDuty) SaveDuty(_ context.Context, driverID string, at time.Time, lat, lng *float64) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.saves++
	r, ok := f.rows[driverID]
	if !ok {
		r = domain.DriverDuty{DriverID: driverID, Since: at}
	}
	r.LastSeenAt = at
	if lat != nil {
		r.Lat, r.Lng = lat, lng
	}
	f.rows[driverID] = r
	return nil
}

func (f *fakeDuty) EndDuty(_ context.Context, driverID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.rows, driverID)
	return nil
}

func (f *fakeDuty) OnDuty(_ context.Context, seenSince time.Time) ([]domain.DriverDuty, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []domain.DriverDuty
	for _, r := range f.rows {
		if !r.LastSeenAt.Before(seenSince) {
			out = append(out, r)
		}
	}
	return out, nil
}

func (f *fakeDuty) ExpireDuty(_ context.Context, silentSince time.Time) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []string
	for id, r := range f.rows {
		if r.LastSeenAt.Before(silentSince) {
			out = append(out, id)
			delete(f.rows, id)
		}
	}
	slices.Sort(out)
	return out, nil
}

type recordingDutyAlerts struct{ ended []string }

func (r *recordingDutyAlerts) DutyEnded(_ context.Context, driverID string) {
	r.ended = append(r.ended, driverID)
}

func TestSetDuty_keepsDutyInPostgresToo(t *testing.T) {
	svc := newRideService(newFakeRideStore())
	duty := newFakeDuty()
	svc.SetDutyStore(duty)
	ctx := context.Background()

	if err := svc.SetDuty(ctx, "auto", true, &LatLng{Lat: 28.61, Lng: 77.23}); err != nil {
		t.Fatalf("SetDuty(on): %v", err)
	}
	r, ok := duty.rows["auto"]
	if !ok || !r.LastSeenAt.Equal(testNow) || r.Lat == nil || *r.Lat != 28.61 {
		t.Fatalf("row = %+v, %v; want on duty at testNow, at 28.61", r, ok)
	}
	// A driver who can't drive isn't put on duty anywhere.
	if err := svc.SetDuty(ctx, "pending", true, nil); err == nil {
		t.Fatal("SetDuty(pending): want an error")
	}
	if _, ok := duty.rows["pending"]; ok {
		t.Error("an uncleared driver was saved on duty")
	}
	if err := svc.SetDuty(ctx, "auto", false, nil); err != nil {
		t.Fatalf("SetDuty(off): %v", err)
	}
	if _, ok := duty.rows["auto"]; ok {
		t.Error("going off duty left the row on duty")
	}
}

// After a restart, whoever was on duty is back in presence as of when their
// app last reported in: the fresh ones are alerted again at once, the quiet
// ones aren't mistaken for fresh.
func TestRestorePresence(t *testing.T) {
	lat, lng := gateLat, gateLng
	duty := newFakeDuty(
		domain.DriverDuty{DriverID: "fresh", LastSeenAt: testNow.Add(-3 * time.Minute), Lat: &lat, Lng: &lng},
		domain.DriverDuty{DriverID: "quiet", LastSeenAt: testNow.Add(-30 * time.Minute), Lat: &lat, Lng: &lng},
		domain.DriverDuty{DriverID: "gone", LastSeenAt: testNow.Add(-3 * time.Hour), Lat: &lat, Lng: &lng},
		domain.DriverDuty{DriverID: "no-gps", LastSeenAt: testNow.Add(-time.Minute)},
	)
	tracker := memstore.NewDriverTracker(geo.DefaultResolution)

	n, err := RestorePresence(context.Background(), duty, tracker, testNow)
	if err != nil || n != 3 {
		t.Fatalf("RestorePresence = %d, %v; want 3 (all but gone)", n, err)
	}
	near, _ := tracker.FindNearbyDrivers(lat, lng, 1000, testNow.Add(-presenceFresh), 0)
	if len(near) != 1 || near[0].Driver.ID != "fresh" {
		t.Errorf("fresh drivers near = %+v, want only fresh", near)
	}
	if _, ok := tracker.Get("gone"); ok {
		t.Error("a driver silent for hours was restored")
	}
}

func TestWatchdog_takesSilentDriversOffDuty(t *testing.T) {
	duty := newFakeDuty(
		domain.DriverDuty{DriverID: "silent", LastSeenAt: testNow.Add(-dutySilence - time.Minute)},
		domain.DriverDuty{DriverID: "here", LastSeenAt: testNow.Add(-5 * time.Minute)},
	)
	presence := &fakePresence{online: map[string]bool{"silent": true, "here": true}}
	alerts := &recordingDutyAlerts{}
	w, _, _, _ := newWatchTest()
	w.WatchDuty(duty, presence, alerts)

	if n := w.Tick(context.Background()); n != 1 {
		t.Errorf("Tick acted on %d, want 1", n)
	}
	if presence.online["silent"] || !presence.online["here"] {
		t.Errorf("presence = %v, want only here", presence.online)
	}
	if !slices.Equal(alerts.ended, []string{"silent"}) {
		t.Errorf("told %v, want silent", alerts.ended)
	}
	if n := w.Tick(context.Background()); n != 0 {
		t.Errorf("second Tick acted on %d, want 0", n)
	}
}

func TestDutyEnded_tellsTheDriver(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	_ = tokens.SaveForDriver(context.Background(), "auto", "tok-auto")
	svc.DutyEnded(context.Background(), "auto")
	svc.Wait()
	m := sender.byToken()["tok-auto"]
	if m.Title != "You're off duty" || m.Data["type"] != pushTypeDutyOff || !strings.Contains(m.Body, "2 hours") {
		t.Errorf("message = %+v", m)
	}
}
