package domain

import "time"

// DriverDuty is a driver's on-duty state as PostgreSQL keeps it, so the
// in-memory presence index can be rebuilt after a restart. Lat and Lng are
// nil when the app had no position to report.
type DriverDuty struct {
	DriverID   string
	Since      time.Time
	LastSeenAt time.Time
	Lat, Lng   *float64
}
