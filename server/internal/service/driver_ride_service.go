package service

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/pkg/geo"
)

// ErrDriverNotCleared is returned when a driver who hasn't finished KYC tries
// to see or take rides.
var ErrDriverNotCleared = errors.New("finish document verification to start taking rides")

// ErrTransmissionMismatch is returned when a driver tries to accept a ride in
// a car whose gearbox they didn't sign up to drive.
var ErrTransmissionMismatch = errors.New("this ride's car has a gearbox you don't drive")

// ErrRideClash is returned when accepting a ride would overlap one the driver
// already has.
var ErrRideClash = errors.New("this ride overlaps one you've already accepted")

// ErrRideInProgress is returned when a driver tries to start a ride while
// another is still underway.
var ErrRideInProgress = errors.New("finish your current ride before starting another")

const (
	// requestRadiusM is how far from the driver an open ride may start and
	// still appear in their feed — roughly a metro area, since rides are
	// booked ahead and the driver travels to the pickup.
	requestRadiusM = 50_000

	// requestGrace keeps a ride whose start time has just passed in the feed,
	// so a customer who booked "now" can still be picked up.
	requestGrace = 30 * time.Minute

	// rideGap is the minimum gap between two rides a driver holds: time to
	// get from one drop-off to the next pickup.
	rideGap = 30 * time.Minute

	maxRequests = 100
	maxMyRides  = 200
)

// DriverRideStore is the slice of persistence this service needs, declared
// consumer-side so it stays testable with a fake.
type DriverRideStore interface {
	ListOpen(ctx context.Context, driverID string, from time.Time, limit int) ([]domain.RideBooking, error)
	ListForDriver(ctx context.Context, driverID string, limit int) ([]domain.RideBooking, error)
	FindByID(ctx context.Context, id string) (domain.RideBooking, error)
	Accept(ctx context.Context, id, driverID string, at time.Time) (domain.RideBooking, error)
	Advance(ctx context.Context, id, driverID string, from, to domain.RideStatus, at time.Time) (domain.RideBooking, error)
	Release(ctx context.Context, id, driverID string) error
	Decline(ctx context.Context, id, driverID string) error
	Earnings(ctx context.Context, driverID string, today, week, month time.Time) (domain.DriverEarnings, error)
}

// DriverProfileReader reads the KYC fields that decide what a driver may
// take: their KYC status and which gearboxes they drive.
type DriverProfileReader interface {
	FindProfile(ctx context.Context, driverID string) (domain.DriverProfile, error)
}

// DriverPresence is the live online/offline index (memstore.DriverTracker).
type DriverPresence interface {
	Register(d domain.Driver)
	UpdateLocation(driverID string, loc domain.Location) error
	Remove(driverID string)
}

// LatLng is a point the driver app reports.
type LatLng struct{ Lat, Lng float64 }

// DriverRideService runs the driver side of a booking's life: the open
// requests feed, accepting, the arrive → start → complete steps, handing a
// ride back, and the earnings summary.
//
// Rides are booked ahead of time, so there is no push dispatch yet: every
// eligible online driver sees the open requests near them and the first to
// accept gets the ride (the store's conditional UPDATE decides the race).
type DriverRideService struct {
	store    DriverRideStore
	profiles DriverProfileReader
	presence DriverPresence
	now      func() time.Time
}

// NewDriverRideService wires the service to its store, the KYC profile
// reader and the live presence index.
func NewDriverRideService(store DriverRideStore, profiles DriverProfileReader, presence DriverPresence) *DriverRideService {
	return &DriverRideService{store: store, profiles: profiles, presence: presence, now: time.Now}
}

// Requests returns the open rides driverID can take, soonest first. With a
// location, rides further than requestRadiusM are left out and each carries
// its distance. The customer's details stay hidden until a ride is accepted.
func (s *DriverRideService) Requests(ctx context.Context, driverID string, at *LatLng) ([]domain.DriverRide, error) {
	profile, err := s.clearedProfile(ctx, driverID)
	if err != nil {
		return nil, err
	}
	rows, err := s.store.ListOpen(ctx, driverID, s.now().Add(-requestGrace), maxRequests)
	if err != nil {
		return nil, err
	}

	out := []domain.DriverRide{}
	for _, rb := range rows {
		ride, plan, ok := toDriverRide(rb, false)
		if !ok || !canDrive(profile.Transmission, plan.Car) {
			continue
		}
		if at != nil {
			d := geo.HaversineMeters(at.Lat, at.Lng, ride.Pickup.Lat, ride.Pickup.Lng)
			if d > requestRadiusM {
				continue
			}
			ride.DistanceM = &d
		}
		out = append(out, ride)
	}
	return out, nil
}

// MyRides returns every ride assigned to driverID — upcoming, underway and
// finished — latest scheduled first.
func (s *DriverRideService) MyRides(ctx context.Context, driverID string) ([]domain.DriverRide, error) {
	rows, err := s.store.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return nil, err
	}
	out := []domain.DriverRide{}
	for _, rb := range rows {
		if ride, _, ok := toDriverRide(rb, true); ok {
			out = append(out, ride)
		}
	}
	return out, nil
}

// Accept assigns the open ride rideID to driverID, provided they're cleared,
// drive its gearbox, and have nothing else booked over the same hours.
func (s *DriverRideService) Accept(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	profile, err := s.clearedProfile(ctx, driverID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	target, err := s.store.FindByID(ctx, rideID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	if target.Booking.Status != domain.RideStatusRequested {
		return domain.DriverRide{}, repository.ErrRideUnavailable
	}
	_, plan, ok := toDriverRide(target, false)
	if !ok {
		return domain.DriverRide{}, repository.ErrRideUnavailable
	}
	if !canDrive(profile.Transmission, plan.Car) {
		return domain.DriverRide{}, ErrTransmissionMismatch
	}

	mine, err := s.store.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return domain.DriverRide{}, err
	}
	for _, rb := range mine {
		if !holdsDriver(rb.Booking.Status) {
			continue
		}
		other, otherPlan, ok := toDriverRide(rb, false)
		if ok && overlaps(plan, otherPlan) {
			slog.InfoContext(ctx, "ride accept refused: clash",
				"driverId", driverID, "rideId", rideID, "clashesWith", other.ID)
			return domain.DriverRide{}, ErrRideClash
		}
	}

	rb, err := s.store.Accept(ctx, rideID, driverID, s.now())
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "ride accepted", "driverId", driverID, "rideId", rideID)
	ride, _, _ := toDriverRide(rb, true)
	return ride, nil
}

// Decline hides an open ride from driverID's feed.
func (s *DriverRideService) Decline(ctx context.Context, driverID, rideID string) error {
	return s.store.Decline(ctx, rideID, driverID)
}

// Arrive marks driverID as at the pickup of their accepted ride.
func (s *DriverRideService) Arrive(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	return s.advance(ctx, driverID, rideID, domain.RideStatusAccepted, domain.RideStatusArrived)
}

// Start begins the ride once the driver is at the pickup. A driver drives one
// car at a time, so it's refused while another ride is underway.
func (s *DriverRideService) Start(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	mine, err := s.store.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return domain.DriverRide{}, err
	}
	for _, rb := range mine {
		if rb.Booking.Status == domain.RideStatusInProgress && rb.Booking.ID != rideID {
			return domain.DriverRide{}, ErrRideInProgress
		}
	}
	return s.advance(ctx, driverID, rideID, domain.RideStatusArrived, domain.RideStatusInProgress)
}

// Complete finishes a ride that is underway.
func (s *DriverRideService) Complete(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	return s.advance(ctx, driverID, rideID, domain.RideStatusInProgress, domain.RideStatusCompleted)
}

// Release hands an accepted ride back to the open pool, before it starts.
func (s *DriverRideService) Release(ctx context.Context, driverID, rideID string) error {
	if err := s.store.Release(ctx, rideID, driverID); err != nil {
		return err
	}
	slog.InfoContext(ctx, "ride released", "driverId", driverID, "rideId", rideID)
	return nil
}

// Earnings sums driverID's completed rides for today, this week (from
// Monday) and this month, in IST, and over all time.
func (s *DriverRideService) Earnings(ctx context.Context, driverID string) (domain.DriverEarnings, error) {
	now := s.now().In(ist)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, ist)
	daysSinceMonday := (int(today.Weekday()) + 6) % 7
	week := today.AddDate(0, 0, -daysSinceMonday)
	month := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, ist)
	return s.store.Earnings(ctx, driverID, today, week, month)
}

// SetDuty puts driverID online (optionally at a location) or takes them
// offline in the live presence index. Going online requires cleared KYC.
func (s *DriverRideService) SetDuty(ctx context.Context, driverID string, online bool, at *LatLng) error {
	if !online {
		s.presence.Remove(driverID)
		return nil
	}
	if _, err := s.clearedProfile(ctx, driverID); err != nil {
		return err
	}
	s.presence.Register(domain.Driver{ID: driverID, Status: domain.DriverStatusAvailable})
	if at != nil {
		return s.presence.UpdateLocation(driverID, domain.Location{Lat: at.Lat, Lng: at.Lng})
	}
	return nil
}

func (s *DriverRideService) advance(ctx context.Context, driverID, rideID string, from, to domain.RideStatus) (domain.DriverRide, error) {
	rb, err := s.store.Advance(ctx, rideID, driverID, from, to, s.now())
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "ride advanced", "driverId", driverID, "rideId", rideID, "status", to)
	ride, _, _ := toDriverRide(rb, true)
	return ride, nil
}

// clearedProfile returns driverID's profile if their KYC lets them drive.
// Submitted counts until there is a review tool to move drivers to verified.
func (s *DriverRideService) clearedProfile(ctx context.Context, driverID string) (domain.DriverProfile, error) {
	p, err := s.profiles.FindProfile(ctx, driverID)
	if err != nil {
		return domain.DriverProfile{}, err
	}
	if p.KYCStatus != domain.KYCSubmitted && p.KYCStatus != domain.KYCVerified {
		return domain.DriverProfile{}, ErrDriverNotCleared
	}
	return p, nil
}

// toDriverRide renders a stored booking for the driver app. ok is false for
// a booking whose details can't be read; callers skip those rather than fail
// the whole list.
func toDriverRide(rb domain.RideBooking, withCustomer bool) (domain.DriverRide, tripPlan, bool) {
	b := rb.Booking
	plan, err := parseTripPlan(b.TripType, b.Details)
	if err != nil {
		slog.Warn("ride skipped: unreadable details", "rideId", b.ID, "error", err)
		return domain.DriverRide{}, tripPlan{}, false
	}
	if b.ScheduledAt != nil {
		plan.ScheduledAt = *b.ScheduledAt
	}
	fare, estimated := b.FarePaise, b.FareEstimated
	if fare == 0 {
		fare, estimated = plan.Fare()
	}
	ride := domain.DriverRide{
		ID:               b.ID,
		TripType:         b.TripType,
		Status:           b.Status,
		ScheduledAt:      plan.ScheduledAt,
		EndsAt:           plan.EndsAt(),
		FarePaise:        fare,
		FareEstimated:    estimated,
		Pickup:           plan.Pickup,
		Destination:      plan.Destination,
		Stops:            plan.Stops,
		Hours:            plan.Hours,
		EstimatedMinutes: plan.EstimatedMinutes,
		Car:              plan.Car,
		AcceptedAt:       b.AcceptedAt,
		ArrivedAt:        b.ArrivedAt,
		StartedAt:        b.StartedAt,
		CompletedAt:      b.CompletedAt,
	}
	if withCustomer {
		c := rb.Customer
		ride.Customer = &c
	}
	return ride, plan, true
}

// canDrive reports whether a driver of gearbox d can drive car. A trip that
// names no car (multi-stop) or no gearbox suits anyone.
func canDrive(d domain.DriverTransmission, car *domain.RideCar) bool {
	if car == nil || car.Transmission == "" || d == "" || d == domain.DriverTransmissionBoth {
		return true
	}
	return string(d) == car.Transmission
}

// holdsDriver reports whether a ride in status s still occupies its driver.
func holdsDriver(s domain.RideStatus) bool {
	return s == domain.RideStatusAccepted || s == domain.RideStatusArrived || s == domain.RideStatusInProgress
}

// overlaps reports whether two rides, each padded by rideGap, share any time.
func overlaps(a, b tripPlan) bool {
	return a.ScheduledAt.Before(b.EndsAt().Add(rideGap)) && b.ScheduledAt.Before(a.EndsAt().Add(rideGap))
}
