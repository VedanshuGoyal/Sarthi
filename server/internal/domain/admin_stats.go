package domain

import "time"

// AdminStats is the ops dashboard's numbers (GET /admin/stats): accounts,
// the KYC queue, who is on duty, bookings by status, completed-ride money
// over IST day windows, and what is owed to drivers. Money is integer paise.
type AdminStats struct {
	// AsOf is when the numbers were read, in IST.
	AsOf time.Time `json:"asOf"`
	// CommissionPercent is MOJUD's cut (COMMISSION_PERCENT), e.g. 13 or 12.5.
	CommissionPercent float64 `json:"commissionPercent"`

	Users        StatsUsers `json:"users"`
	DriversByKYC StatsKYC   `json:"driversByKyc"`
	// DriversOnDuty counts drivers in the live presence index: online and
	// not since gone offline. Nil when no index is wired.
	DriversOnDuty    *int                `json:"driversOnDuty,omitempty"`
	BookingsByStatus StatsBookings       `json:"bookingsByStatus"`
	CompletedRides   StatsCompletedRides `json:"completedRides"`
	PayoutsDue       StatsPayoutsDue     `json:"payoutsDue"`
}

// StatsUsers counts accounts: customers (users) and drivers.
type StatsUsers struct {
	Customers int `json:"customers"`
	Drivers   int `json:"drivers"`
}

// StatsKYC counts drivers by [KYCStatus].
type StatsKYC struct {
	Incomplete int `json:"incomplete"`
	Submitted  int `json:"submitted"`
	Verified   int `json:"verified"`
	Rejected   int `json:"rejected"`
}

// StatsBookings counts bookings by where they are now. Open and Expired
// split the requested ones the way the customer app sees them; Accepted
// includes arrived (driver assigned, trip not started). Total is every row.
type StatsBookings struct {
	Open       int `json:"open"`
	Accepted   int `json:"accepted"`
	InProgress int `json:"inProgress"`
	Completed  int `json:"completed"`
	Cancelled  int `json:"cancelled"`
	Expired    int `json:"expired"`
	Total      int `json:"total"`
}

// StatsCompletedRides is completed-ride money over three windows of IST
// calendar days ending now: today, the last 7 and the last 30.
type StatsCompletedRides struct {
	Today      StatsRideWindow `json:"today"`
	Last7Days  StatsRideWindow `json:"last7Days"`
	Last30Days StatsRideWindow `json:"last30Days"`
}

// StatsRideWindow is the rides completed since From, their summed fares, and
// MOJUD's commission on those fares at the current rate.
type StatsRideWindow struct {
	From            time.Time `json:"from"`
	Rides           int       `json:"rides"`
	GrossFarePaise  int64     `json:"grossFarePaise"`
	CommissionPaise int64     `json:"commissionPaise"`
}

// StatsPayoutsDue is what MOJUD owes drivers now — the total of the payouts
// list: drivers owed, rides behind it, and the amount after commission.
type StatsPayoutsDue struct {
	Drivers     int   `json:"drivers"`
	Rides       int   `json:"rides"`
	AmountPaise int64 `json:"amountPaise"`
}
