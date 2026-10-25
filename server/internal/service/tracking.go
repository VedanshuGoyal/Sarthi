package service

import (
	"errors"
	"math"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// ErrNotTracking is returned when a customer asks where their driver is
// outside the live-tracking window, or before a driver is assigned.
var ErrNotTracking = errors.New("your driver's location is shared from an hour before the trip until it ends")

// ErrInvalidLocation is returned for a shared position that isn't a real
// point on Earth.
var ErrInvalidLocation = errors.New("lat must be within ±90 and lng within ±180")

const (
	// trackingLead is how long before a ride's start the customer can watch
	// their driver on the way — and the driver app starts sharing. Rides
	// are booked ahead, so an accepted ride days out shares nothing.
	trackingLead = 60 * time.Minute

	// liveFixMaxAge is how old a shared position may be and still be shown;
	// an older one is treated as no position at all.
	liveFixMaxAge = 30 * time.Minute
)

// sharesLocation reports whether a ride in status, starting at start, is in
// its live-tracking window at now: the driver is at the pickup or driving,
// or has the ride and it starts within trackingLead.
func sharesLocation(status domain.RideStatus, start, now time.Time) bool {
	switch status {
	case domain.RideStatusArrived, domain.RideStatusInProgress:
		return true
	case domain.RideStatusAccepted:
		return !now.Before(start.Add(-trackingLead))
	default:
		return false
	}
}

// newLiveLocation validates a position a driver's app shared at now. A
// heading, when given, is folded into [0, 360).
func newLiveLocation(lat, lng float64, heading *float64, now time.Time) (domain.LiveLocation, error) {
	if math.IsNaN(lat) || math.IsNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return domain.LiveLocation{}, ErrInvalidLocation
	}
	loc := domain.LiveLocation{Lat: lat, Lng: lng, UpdatedAt: now}
	if heading != nil && !math.IsNaN(*heading) && !math.IsInf(*heading, 0) {
		h := math.Mod(*heading, 360)
		if h < 0 {
			h += 360
		}
		loc.Heading = &h
	}
	return loc, nil
}
