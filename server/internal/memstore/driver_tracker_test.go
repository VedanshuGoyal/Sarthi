package memstore

import (
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/pkg/geo"
)

// Reference point: Bengaluru, MG Road.
const (
	baseLat = 12.9756
	baseLng = 77.6050
)

func TestFindNearbyDrivers_RadiusAndOrdering(t *testing.T) {
	tr := NewDriverTracker(geo.DefaultResolution)

	// ~150m east of base.
	mustUpdate(t, tr, "near", baseLat, baseLng+0.0014)
	// ~600m east of base.
	mustUpdate(t, tr, "mid", baseLat, baseLng+0.0055)
	// ~5km east of base — well outside a 1km search.
	mustUpdate(t, tr, "far", baseLat, baseLng+0.045)

	got, err := tr.FindNearbyDrivers(baseLat, baseLng, 1000, time.Time{}, 0)
	if err != nil {
		t.Fatalf("FindNearbyDrivers: %v", err)
	}

	if len(got) != 2 {
		t.Fatalf("want 2 drivers within 1km, got %d: %+v", len(got), got)
	}
	if got[0].Driver.ID != "near" || got[1].Driver.ID != "mid" {
		t.Fatalf("want nearest-first [near, mid], got [%s, %s]",
			got[0].Driver.ID, got[1].Driver.ID)
	}
	if got[0].DistanceM > got[1].DistanceM {
		t.Fatalf("results not sorted by distance: %v > %v",
			got[0].DistanceM, got[1].DistanceM)
	}
}

func TestUpdateLocation_ReindexesAcrossCells(t *testing.T) {
	tr := NewDriverTracker(geo.DefaultResolution)

	mustUpdate(t, tr, "d1", baseLat, baseLng)
	// Move the driver ~5km away; they should leave the original cell and only
	// appear in searches around the new position.
	mustUpdate(t, tr, "d1", baseLat+0.045, baseLng)

	if got, _ := tr.FindNearbyDrivers(baseLat, baseLng, 1000, time.Time{}, 0); len(got) != 0 {
		t.Fatalf("driver should have moved out of original area, got %d", len(got))
	}
	if got, _ := tr.FindNearbyDrivers(baseLat+0.045, baseLng, 1000, time.Time{}, 0); len(got) != 1 {
		t.Fatalf("driver should be found at new area, got %d", len(got))
	}
}

func TestFindNearbyDrivers_SkipsUnavailable(t *testing.T) {
	tr := NewDriverTracker(geo.DefaultResolution)
	mustUpdate(t, tr, "busy", baseLat, baseLng)
	tr.SetStatus("busy", domain.DriverStatusOnTrip)

	if got, _ := tr.FindNearbyDrivers(baseLat, baseLng, 1000, time.Time{}, 0); len(got) != 0 {
		t.Fatalf("on_trip driver must not be matched, got %d", len(got))
	}
}

// A driver whose app went quiet without going offline isn't found, isn't
// counted as on duty, and is eventually dropped.
func TestDriverTracker_StalePresenceFades(t *testing.T) {
	tr := NewDriverTracker(geo.DefaultResolution)
	clock := time.Date(2026, 11, 17, 10, 0, 0, 0, time.UTC)
	tr.now = func() time.Time { return clock }

	if err := tr.UpdateLocation("quiet", domain.Location{Lat: baseLat, Lng: baseLng, UpdatedAt: clock}); err != nil {
		t.Fatal(err)
	}
	clock = clock.Add(20 * time.Minute)
	if err := tr.UpdateLocation("fresh", domain.Location{Lat: baseLat, Lng: baseLng + 0.005, UpdatedAt: clock}); err != nil {
		t.Fatal(err)
	}
	tr.Register(domain.Driver{ID: "no-fix"}) // online, location not shared

	cutoff := clock.Add(-10 * time.Minute)
	got, err := tr.FindNearbyDrivers(baseLat, baseLng, 1000, cutoff, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Driver.ID != "fresh" {
		t.Errorf("found %+v, want only the fresh driver (the quiet one is nearer)", got)
	}
	if n := tr.CountSeenSince(cutoff); n != 2 {
		t.Errorf("on duty = %d, want 2 (fresh and no-fix)", n)
	}

	clock = clock.Add(presenceEvictAfter)
	tr.Register(domain.Driver{ID: "fresh"})
	if _, ok := tr.Get("quiet"); ok {
		t.Error("a driver silent for over an hour is still tracked")
	}
	if _, ok := tr.Get("fresh"); !ok {
		t.Error("a driver who just reported in was evicted")
	}
}

func mustUpdate(t *testing.T, tr *DriverTracker, id string, lat, lng float64) {
	t.Helper()
	if err := tr.UpdateLocation(id, domain.Location{Lat: lat, Lng: lng}); err != nil {
		t.Fatalf("UpdateLocation(%s): %v", id, err)
	}
}
