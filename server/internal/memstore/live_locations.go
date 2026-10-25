package memstore

import (
	"sync"

	"github.com/sarthi/server/internal/domain"
)

// LiveLocations holds the latest position each driver's app shared while on
// the way to, or driving, a customer — what the customer's live map reads.
//
// It is deliberately separate from DriverTracker: that index is "who is
// online for new requests", and its UpdateLocation upserts a driver as
// available. A driver sharing their position for a ride they already hold
// must not be put back in line for new-request alerts by doing so.
//
// One entry per driver, overwritten on each fix, so it is bounded by the
// number of drivers. Readers judge freshness from UpdatedAt.
type LiveLocations struct {
	mu       sync.RWMutex
	byDriver map[string]domain.LiveLocation
}

// NewLiveLocations creates an empty store.
func NewLiveLocations() *LiveLocations {
	return &LiveLocations{byDriver: make(map[string]domain.LiveLocation)}
}

// Put records driverID's latest fix.
func (l *LiveLocations) Put(driverID string, loc domain.LiveLocation) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.byDriver[driverID] = loc
}

// Latest returns driverID's last fix, if they have shared one since the
// server started.
func (l *LiveLocations) Latest(driverID string) (domain.LiveLocation, bool) {
	l.mu.RLock()
	defer l.mu.RUnlock()
	loc, ok := l.byDriver[driverID]
	return loc, ok
}
