// Package memstore holds the platform's hot, real-time state in memory. It is
// the deliberate replacement for Redis: there is no external cache, so every
// high-frequency read/write (driver GPS, ride matchmaking) lives here behind a
// sync.RWMutex. PostgreSQL remains the source of truth for anything that must
// survive a restart; memstore is rebuilt from live device connections.
package memstore

import (
	"sort"
	"sync"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/pkg/geo"
)

// DriverTracker is a concurrency-safe spatial index of online drivers.
//
// It maintains three maps under a single RWMutex:
//   - drivers:    driverID -> latest known Driver state
//   - cellIndex:  H3 cell  -> set of driverIDs currently in that cell
//   - driverCell: driverID -> the cell it is presently indexed under
//
// cellIndex is what makes FindNearbyDrivers cheap: instead of scanning every
// driver, we look up only the handful of cells covering the search radius.
// driverCell lets UpdateLocation move a driver between cells in O(1) when they
// cross a hex boundary.
type DriverTracker struct {
	mu sync.RWMutex

	resolution int
	drivers    map[string]*domain.Driver
	cellIndex  map[geo.Cell]map[string]struct{}
	driverCell map[string]geo.Cell
}

// NewDriverTracker creates an empty tracker indexing at the given H3
// resolution. Pass geo.DefaultResolution unless you have a reason not to.
func NewDriverTracker(resolution int) *DriverTracker {
	return &DriverTracker{
		resolution: resolution,
		drivers:    make(map[string]*domain.Driver),
		cellIndex:  make(map[geo.Cell]map[string]struct{}),
		driverCell: make(map[string]geo.Cell),
	}
}

// NearbyDriver is a matched driver together with their straight-line distance
// from the query point, in metres.
type NearbyDriver struct {
	Driver    domain.Driver `json:"driver"`
	DistanceM float64       `json:"distanceM"`
}

// Register adds or refreshes a driver's persistent metadata (name, vehicle)
// and marks them available, without yet placing a location. Call this when a
// driver goes online; their first UpdateLocation will index them spatially.
func (t *DriverTracker) Register(d domain.Driver) {
	t.mu.Lock()
	defer t.mu.Unlock()

	existing, ok := t.drivers[d.ID]
	if !ok {
		if d.Status == "" {
			d.Status = domain.DriverStatusAvailable
		}
		copy := d
		t.drivers[d.ID] = &copy
		return
	}
	existing.Name = d.Name
	existing.Vehicle = d.Vehicle
	if d.Status != "" {
		existing.Status = d.Status
	}
}

// UpdateLocation records a driver's latest GPS fix and re-indexes them if they
// have crossed into a new H3 cell. It upserts: a location for an unknown driver
// creates a minimal available entry, so raw GPS frames from the websocket layer
// work without a prior Register call.
func (t *DriverTracker) UpdateLocation(driverID string, loc domain.Location) error {
	cell, err := geo.CellAt(loc.Lat, loc.Lng, t.resolution)
	if err != nil {
		return err
	}
	if loc.UpdatedAt.IsZero() {
		loc.UpdatedAt = time.Now()
	}

	t.mu.Lock()
	defer t.mu.Unlock()

	d, ok := t.drivers[driverID]
	if !ok {
		d = &domain.Driver{ID: driverID, Status: domain.DriverStatusAvailable}
		t.drivers[driverID] = d
	}
	d.Location = loc

	prev, indexed := t.driverCell[driverID]
	if indexed && prev == cell {
		return nil // same bucket — no re-indexing needed
	}
	if indexed {
		t.removeFromCell(prev, driverID)
	}
	t.addToCell(cell, driverID)
	t.driverCell[driverID] = cell
	return nil
}

// SetStatus updates a driver's availability (e.g. on_trip while serving a ride).
// Returns false if the driver is unknown.
func (t *DriverTracker) SetStatus(driverID string, status domain.DriverStatus) bool {
	t.mu.Lock()
	defer t.mu.Unlock()

	d, ok := t.drivers[driverID]
	if !ok {
		return false
	}
	d.Status = status
	return true
}

// Remove drops a driver from the tracker entirely (e.g. on disconnect or going
// offline).
func (t *DriverTracker) Remove(driverID string) {
	t.mu.Lock()
	defer t.mu.Unlock()

	if cell, ok := t.driverCell[driverID]; ok {
		t.removeFromCell(cell, driverID)
		delete(t.driverCell, driverID)
	}
	delete(t.drivers, driverID)
}

// FindNearbyDrivers returns available drivers within radiusMeters of
// (lat, lng), nearest first. limit <= 0 means no cap.
//
// It first asks H3 for the cells covering the search disk (a coarse superset),
// gathers the drivers bucketed in those cells, then filters each by exact
// haversine distance so the radius is honoured precisely.
func (t *DriverTracker) FindNearbyDrivers(lat, lng, radiusMeters float64, limit int) ([]NearbyDriver, error) {
	cells, err := geo.DiskForRadius(lat, lng, radiusMeters, t.resolution)
	if err != nil {
		return nil, err
	}

	t.mu.RLock()
	var results []NearbyDriver
	for _, cell := range cells {
		for driverID := range t.cellIndex[cell] {
			d := t.drivers[driverID]
			if d == nil || d.Status != domain.DriverStatusAvailable {
				continue
			}
			dist := geo.HaversineMeters(lat, lng, d.Location.Lat, d.Location.Lng)
			if dist <= radiusMeters {
				// Copy the value so callers never hold a pointer into the map
				// once we release the lock.
				results = append(results, NearbyDriver{Driver: *d, DistanceM: dist})
			}
		}
	}
	t.mu.RUnlock()

	sort.Slice(results, func(i, j int) bool {
		return results[i].DistanceM < results[j].DistanceM
	})
	if limit > 0 && len(results) > limit {
		results = results[:limit]
	}
	return results, nil
}

// Get returns a copy of a driver's current state and whether they are tracked.
func (t *DriverTracker) Get(driverID string) (domain.Driver, bool) {
	t.mu.RLock()
	defer t.mu.RUnlock()

	d, ok := t.drivers[driverID]
	if !ok {
		return domain.Driver{}, false
	}
	return *d, true
}

// Count returns the number of drivers currently tracked.
func (t *DriverTracker) Count() int {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return len(t.drivers)
}

// addToCell / removeFromCell mutate the spatial index. Both assume the caller
// already holds the write lock.

func (t *DriverTracker) addToCell(cell geo.Cell, driverID string) {
	set := t.cellIndex[cell]
	if set == nil {
		set = make(map[string]struct{})
		t.cellIndex[cell] = set
	}
	set[driverID] = struct{}{}
}

func (t *DriverTracker) removeFromCell(cell geo.Cell, driverID string) {
	set := t.cellIndex[cell]
	if set == nil {
		return
	}
	delete(set, driverID)
	if len(set) == 0 {
		delete(t.cellIndex, cell) // keep the index from leaking empty cells
	}
}
