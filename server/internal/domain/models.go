// Package domain holds the core, transport-agnostic types of the Sarthi
// platform. These structs are the shared vocabulary used by every layer
// (api, websocket, memstore, repository, service) so they intentionally
// carry no behaviour beyond JSON tags.
package domain

import "time"

// DriverStatus is the availability of a driver for matching.
type DriverStatus string

const (
	DriverStatusOffline   DriverStatus = "offline"   // not accepting jobs
	DriverStatusAvailable DriverStatus = "available" // online, can be matched
	DriverStatusOnTrip    DriverStatus = "on_trip"   // online but busy
)

// RideStatus tracks a ride through its lifecycle.
type RideStatus string

const (
	RideStatusRequested  RideStatus = "requested"   // rider asked, no driver yet
	RideStatusMatched    RideStatus = "matched"     // offered to a driver
	RideStatusAccepted   RideStatus = "accepted"    // driver accepted, en route
	RideStatusArrived    RideStatus = "arrived"     // driver at pickup
	RideStatusInProgress RideStatus = "in_progress" // rider on board
	RideStatusCompleted  RideStatus = "completed"   // finished, fare settled
	RideStatusCancelled  RideStatus = "cancelled"   // aborted by either party
)

// Location is a geographic point reported by a device, with the bearing the
// device was moving and the moment it was observed.
type Location struct {
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	Heading   float64   `json:"heading"` // bearing in degrees clockwise from North
	UpdatedAt time.Time `json:"updatedAt"`
}

// Driver is a registered driver together with their live state. The persistent
// fields (ID, Name, Vehicle) come from PostgreSQL; Status and Location are the
// real-time fields held in memstore and never trusted from the database.
type Driver struct {
	ID       string       `json:"id"`
	Name     string       `json:"name"`
	Vehicle  string       `json:"vehicle"`
	Status   DriverStatus `json:"status"`
	Location Location     `json:"location"`
}

// Ride is a single trip request and its full lifecycle. Completed rides are the
// source of truth for financials, so monetary amounts are stored as integer
// minor units (cents) to avoid floating-point drift.
type Ride struct {
	ID          string     `json:"id"`
	RiderID     string     `json:"riderId"`
	DriverID    string     `json:"driverId,omitempty"`
	Status      RideStatus `json:"status"`
	Pickup      Location   `json:"pickup"`
	Dropoff     Location   `json:"dropoff"`
	FareCents   int64      `json:"fareCents"`
	RequestedAt time.Time  `json:"requestedAt"`
	CompletedAt *time.Time `json:"completedAt,omitempty"`
}
