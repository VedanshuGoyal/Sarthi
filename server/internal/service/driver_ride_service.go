package service

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"math/big"
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

// ErrRideClosed is returned when a driver tries to accept a ride that starts
// within acceptCutoff. It wraps ErrRideUnavailable, so the app drops it from
// the feed like a ride someone else took.
var ErrRideClosed = fmt.Errorf("this ride starts too soon to take: %w", repository.ErrRideUnavailable)

// ErrRideClash is returned when accepting a ride would overlap one the driver
// already has.
var ErrRideClash = errors.New("this ride overlaps one you've already accepted")

// ErrRideInProgress is returned when a driver tries to start a ride while
// another is still underway.
var ErrRideInProgress = errors.New("finish your current ride before starting another")

// ErrCannotRateRide is returned when a driver rates a ride that isn't
// completed, isn't theirs, or that they already rated.
var ErrCannotRateRide = fmt.Errorf("you can rate a customer once, after the ride is completed: %w",
	repository.ErrRideStateConflict)

// ErrStartOTPIncorrect is returned when the code a driver enters to start a
// ride doesn't match the one in the customer's app.
var ErrStartOTPIncorrect = errors.New("that code doesn't match — ask the customer for the code in their app")

// ErrStartOTPReset is returned on the wrong attempt that uses up the
// allowance: the ride gets a new code, which the customer's app now shows.
var ErrStartOTPReset = errors.New("too many wrong codes — the customer's app now shows a new one")

// ErrStartLocked is matched (errors.Is) by a [*StartLockedError]: the ride
// has had too many wrong codes and refuses any for a while.
var ErrStartLocked = errors.New("too many wrong codes for this ride")

// StartLockedError says how long a locked ride refuses start codes.
type StartLockedError struct{ RetryAfter time.Duration }

func (e *StartLockedError) Error() string {
	return fmt.Sprintf("too many wrong codes for this ride — try again in %d minutes",
		int(math.Ceil(e.RetryAfter.Minutes())))
}

// Is makes errors.Is(err, ErrStartLocked) true.
func (e *StartLockedError) Is(target error) bool { return target == ErrStartLocked }

// ErrNoShowTooEarly is matched (errors.Is) by a [*NoShowTooEarlyError]: the
// driver hasn't waited at the pickup long enough to call a no-show.
var ErrNoShowTooEarly = errors.New("wait a little longer for the customer")

// NoShowTooEarlyError says when the driver may close the ride as a no-show.
type NoShowTooEarlyError struct {
	At   time.Time
	Wait time.Duration
}

func (e *NoShowTooEarlyError) Error() string {
	return fmt.Sprintf("give the customer until %s before closing the ride as a no-show", formatClock(e.At))
}

// Is makes errors.Is(err, ErrNoShowTooEarly) true.
func (e *NoShowTooEarlyError) Is(target error) bool { return target == ErrNoShowTooEarly }

// noShowWait is how long a driver waits at the pickup — from the later of
// arriving and the booked start — before they may close the ride as a
// no-show.
const noShowWait = 15 * time.Minute

const (
	// requestRadiusM is how far from the driver an open ride may start and
	// still appear in their feed — roughly a metro area, since rides are
	// booked ahead and the driver travels to the pickup.
	requestRadiusM = 50_000

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
	Accept(ctx context.Context, id, driverID string, at time.Time, startOTP string) (domain.RideBooking, error)
	SetStartOTP(ctx context.Context, id, driverID, startOTP string) error
	Advance(ctx context.Context, id, driverID string, from, to domain.RideStatus, at time.Time) (domain.RideBooking, error)
	Complete(ctx context.Context, id, driverID string, farePaise int64, at time.Time) (domain.RideBooking, error)
	Release(ctx context.Context, id, driverID string) error
	NoShow(ctx context.Context, id, driverID string, at time.Time, reason string) (domain.RideBooking, error)
	Decline(ctx context.Context, id, driverID string) error
	RateCustomer(ctx context.Context, id, driverID string, rating domain.RideRating) error
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

// StartCodeGuard caps wrong start-code attempts per ride
// (memstore.StartCodeGuard, keyed by ride id): after a few wrong codes the
// code is replaced, and after a few replacements the ride is locked.
type StartCodeGuard interface {
	Allow(ride string) (ok bool, retryAfter time.Duration)
	RecordFailure(ride string) (replace bool, lockedFor time.Duration)
	Succeed(ride string)
}

// LiveLocationSink keeps the positions drivers' apps share while on a ride
// (memstore.LiveLocations).
type LiveLocationSink interface {
	Put(driverID string, loc domain.LiveLocation)
}

// RideAlerter tells the customer how their ride is going — a driver took
// it, is at the pickup, handed it back or finished it — and, for a
// handed-back ride, the
// other drivers near it (NotifyService). Each call returns at once; the
// alerts go out in the background.
type RideAlerter interface {
	DriverAssigned(ctx context.Context, userID string, ride domain.DriverRide, driverName string)
	DriverArrived(ctx context.Context, userID, driverID string, ride domain.DriverRide)
	DriverReleased(ctx context.Context, b domain.Booking, plan tripPlan, driverID string)
	RideCompleted(ctx context.Context, userID string, ride domain.DriverRide)
	CustomerNoShow(ctx context.Context, userID string, ride domain.DriverRide)
}

// LatLng is a point the driver app reports.
type LatLng struct{ Lat, Lng float64 }

// DriverRideService runs the driver side of a booking's life: the open
// requests feed, accepting, the arrive → start → complete steps, handing a
// ride back, and the earnings summary.
//
// Rides are booked ahead of time, so there is no one-driver dispatch: every
// eligible online driver sees the open requests near them (and is pushed a
// "new ride request", see NotifyService) and the first to accept gets the
// ride (the store's conditional UPDATE decides the race).
type DriverRideService struct {
	store    DriverRideStore
	profiles DriverProfileReader
	presence DriverPresence
	codes    StartCodeGuard
	live     LiveLocationSink
	alerts   RideAlerter
	duty     DutyStore // nil: duty lives in presence only
	now      func() time.Time
	newCode  func() (string, error)

	// drivers serialises each driver's accepts and starts: both check the
	// driver's other rides, then write, and two at once could both pass.
	drivers keyedLocks
}

// NewDriverRideService wires the service to its store, the KYC profile
// reader, the live presence index, the start-code attempt limiter, the
// positions shared for customers' live maps and the customer alerts sent on
// accept, arrival and release (nil sends none).
func NewDriverRideService(store DriverRideStore, profiles DriverProfileReader, presence DriverPresence, codes StartCodeGuard, live LiveLocationSink, alerts RideAlerter) *DriverRideService {
	return &DriverRideService{
		store:    store,
		profiles: profiles,
		presence: presence,
		codes:    codes,
		live:     live,
		alerts:   alerts,
		now:      time.Now,
		newCode:  newStartOTP,
	}
}

// Requests returns the open rides driverID can take, soonest first — those
// starting more than acceptCutoff from now. With a
// location, rides further than requestRadiusM are left out and each carries
// its distance. Until a ride is accepted it is approximate (see
// coarseRide): localities instead of addresses, no plate, no customer — and
// the distance is to the rounded pickup, so asking from three places
// doesn't pin down the house.
func (s *DriverRideService) Requests(ctx context.Context, driverID string, at *LatLng) ([]domain.DriverRide, error) {
	profile, err := s.clearedProfile(ctx, driverID)
	if err != nil {
		return nil, err
	}
	rows, err := s.store.ListOpen(ctx, driverID, s.now().Add(acceptCutoff), maxRequests)
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
		if ride, ok := s.assigned(rb); ok {
			out = append(out, ride)
		}
	}
	return out, nil
}

// Accept assigns the open ride rideID to driverID, provided they're cleared,
// drive its gearbox, and have nothing else booked over the same hours.
//
// It is replay-safe: accepting a ride the driver already holds (a retry
// after a lost reply, a double tap) returns it as it stands, rather than
// telling them they lost it.
func (s *DriverRideService) Accept(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	profile, err := s.clearedProfile(ctx, driverID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	// From reading the ride to the accept, one at a time per driver: a
	// double-fired accept on two overlapping rides can't win both, and one
	// fired twice on the same ride sees the first one's result.
	defer s.drivers.lock(driverID)()
	target, err := s.store.FindByID(ctx, rideID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	if held, ok := s.heldBy(target, driverID); ok {
		slog.InfoContext(ctx, "ride accept replayed", "driverId", driverID, "rideId", rideID)
		return held, nil
	}
	if target.Booking.Status != domain.RideStatusRequested {
		return domain.DriverRide{}, repository.ErrRideUnavailable
	}
	_, plan, ok := toDriverRide(target, false)
	if !ok {
		return domain.DriverRide{}, repository.ErrRideUnavailable
	}
	if closedToDrivers(plan.ScheduledAt, s.now()) {
		return domain.DriverRide{}, ErrRideClosed
	}
	if !canDrive(profile.Transmission, plan.Car) {
		return domain.DriverRide{}, ErrTransmissionMismatch
	}

	mine, err := s.store.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return domain.DriverRide{}, err
	}
	for _, rb := range mine {
		if !holdsDriver(rb.Booking.Status) || rb.Booking.ID == rideID {
			continue
		}
		other, otherPlan, ok := toDriverRide(rb, false)
		if ok && overlaps(plan, otherPlan) {
			slog.InfoContext(ctx, "ride accept refused: clash",
				"driverId", driverID, "rideId", rideID, "clashesWith", other.ID)
			return domain.DriverRide{}, ErrRideClash
		}
	}

	code, err := s.newCode()
	if err != nil {
		return domain.DriverRide{}, err
	}
	rb, err := s.store.Accept(ctx, rideID, driverID, s.now(), code)
	if errors.Is(err, repository.ErrRideUnavailable) {
		// Lost the race — unless to this same driver, by another path.
		if now, ferr := s.store.FindByID(ctx, rideID); ferr == nil {
			if held, ok := s.heldBy(now, driverID); ok {
				return held, nil
			}
		}
	}
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "ride accepted", "driverId", driverID, "rideId", rideID)
	ride, _ := s.assigned(rb)
	if s.alerts != nil {
		s.alerts.DriverAssigned(ctx, rb.Booking.UserID, ride, profile.FullName)
	}
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

// Start begins the ride once the driver is at the pickup and enters the code
// from the customer's app. A driver drives one car at a time, so it's refused
// while another ride is underway.
//
// Wrong codes are capped per ride (StartCodeGuard); the attempt that uses up
// the allowance replaces the code, so guessing never gets easier and the
// customer simply reads out the new one. A ride whose codes keep being used
// up is locked for a while ([ErrStartLocked]), so 10,000 guesses can't be
// scripted.
func (s *DriverRideService) Start(ctx context.Context, driverID, rideID, otp string) (domain.DriverRide, error) {
	// One at a time per driver, from the "nothing else underway" check to
	// the start.
	defer s.drivers.lock(driverID)()
	mine, err := s.store.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return domain.DriverRide{}, err
	}
	var target *domain.RideBooking
	for i, rb := range mine {
		if rb.Booking.Status == domain.RideStatusInProgress && rb.Booking.ID != rideID {
			return domain.DriverRide{}, ErrRideInProgress
		}
		if rb.Booking.ID == rideID {
			target = &mine[i]
		}
	}
	// Already started (a retry after a lost reply): nothing to check again.
	if target != nil && target.Booking.Status == domain.RideStatusInProgress {
		ride, _ := s.assigned(*target)
		return ride, nil
	}
	if target == nil || target.Booking.Status != domain.RideStatusArrived {
		return domain.DriverRide{}, repository.ErrRideStateConflict
	}

	if ok, wait := s.codes.Allow(rideID); !ok {
		return domain.DriverRide{}, &StartLockedError{RetryAfter: wait}
	}
	want := target.Booking.StartOTP
	if want == "" || subtle.ConstantTimeCompare([]byte(otp), []byte(want)) != 1 {
		replace, lockedFor := s.codes.RecordFailure(rideID)
		if !replace {
			return domain.DriverRide{}, ErrStartOTPIncorrect
		}
		code, err := s.newCode()
		if err != nil {
			return domain.DriverRide{}, err
		}
		if err := s.store.SetStartOTP(ctx, rideID, driverID, code); err != nil {
			return domain.DriverRide{}, err
		}
		if lockedFor > 0 {
			slog.WarnContext(ctx, "ride start locked after repeated wrong codes",
				"driverId", driverID, "rideId", rideID, "lockedFor", lockedFor)
			return domain.DriverRide{}, &StartLockedError{RetryAfter: lockedFor}
		}
		slog.WarnContext(ctx, "ride start code reset after wrong attempts",
			"driverId", driverID, "rideId", rideID)
		return domain.DriverRide{}, ErrStartOTPReset
	}

	ride, err := s.advance(ctx, driverID, rideID, domain.RideStatusArrived, domain.RideStatusInProgress)
	if err == nil {
		s.codes.Succeed(rideID)
	}
	return ride, err
}

// Complete finishes a ride that is underway.
//
// A trip that ran past its booked hours (plus a grace) is charged for the
// time used on the hourly tariff (see [finalFare]); the ride returned
// carries the final fare and, then, the booked one.
func (s *DriverRideService) Complete(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	rb, err := s.store.FindByID(ctx, rideID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	b := rb.Booking
	if b.DriverID != driverID {
		return domain.DriverRide{}, repository.ErrRideStateConflict
	}
	if b.Status == domain.RideStatusCompleted {
		slog.InfoContext(ctx, "ride step replayed", "driverId", driverID, "rideId", rideID, "status", b.Status)
		ride, _ := s.assigned(rb)
		return ride, nil
	}
	if b.Status != domain.RideStatusInProgress {
		return domain.DriverRide{}, repository.ErrRideStateConflict
	}
	fare := b.FarePaise
	plan, err := planOf(b)
	if err == nil && fare == 0 {
		fare, _ = plan.Fare()
	}
	now := s.now()
	if err == nil && b.StartedAt != nil {
		fare = finalFare(plan, fare, *b.StartedAt, now, false)
	}
	done, err := s.store.Complete(ctx, rideID, driverID, fare, now)
	if errors.Is(err, repository.ErrRideStateConflict) {
		// Completed (or ended by the customer) a moment ago: hand that back.
		if cur, ferr := s.store.FindByID(ctx, rideID); ferr == nil &&
			cur.Booking.DriverID == driverID && cur.Booking.Status == domain.RideStatusCompleted {
			ride, _ := s.assigned(cur)
			return ride, nil
		}
	}
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "ride advanced", "driverId", driverID, "rideId", rideID, "status", domain.RideStatusCompleted,
		"farePaise", done.Booking.FarePaise, "bookedFarePaise", done.Booking.BookedFarePaise)
	ride, _ := s.assigned(done)
	if s.alerts != nil {
		s.alerts.RideCompleted(ctx, done.Booking.UserID, ride)
	}
	return ride, nil
}

// NoShow closes the ride driverID is waiting at the pickup of because the
// customer never came: cancelled by "no_show", so the driver isn't the one
// who cancelled. Allowed from noShowWait after the later of their arrival
// and the booked start ([*NoShowTooEarlyError] before then). The customer
// is told. Asking again once it's closed returns the ride.
func (s *DriverRideService) NoShow(ctx context.Context, driverID, rideID string) (domain.DriverRide, error) {
	rb, err := s.store.FindByID(ctx, rideID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	b := rb.Booking
	if b.DriverID != driverID {
		return domain.DriverRide{}, repository.ErrRideStateConflict
	}
	if b.Status == domain.RideStatusCancelled && b.CancelledBy == domain.CancelledByNoShow {
		ride, _ := s.assigned(rb)
		return ride, nil
	}
	if b.Status != domain.RideStatusArrived {
		return domain.DriverRide{}, repository.ErrRideStateConflict
	}
	now := s.now()
	if at := noShowAt(b); at != nil && now.Before(*at) {
		return domain.DriverRide{}, &NoShowTooEarlyError{At: *at, Wait: at.Sub(now)}
	}
	reason := "The driver waited at the pickup until " + formatClock(now)
	rb, err = s.store.NoShow(ctx, rideID, driverID, now, reason)
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "ride closed as a no-show", "driverId", driverID, "rideId", rideID)
	ride, _ := s.assigned(rb)
	if s.alerts != nil {
		s.alerts.CustomerNoShow(ctx, b.UserID, ride)
	}
	return ride, nil
}

// noShowAt is when the driver of arrived booking b may call a no-show:
// noShowWait after the later of arriving and the booked start. Nil for a
// booking not at the pickup.
func noShowAt(b domain.Booking) *time.Time {
	if b.Status != domain.RideStatusArrived || b.ArrivedAt == nil || b.ScheduledAt == nil {
		return nil
	}
	from := *b.ArrivedAt
	if b.ScheduledAt.After(from) {
		from = *b.ScheduledAt
	}
	at := from.Add(noShowWait)
	return &at
}

// Release hands an accepted ride back to the open pool, before it starts.
// The customer is told, and — while the ride is still open to drivers — the
// other drivers near it are alerted again.
func (s *DriverRideService) Release(ctx context.Context, driverID, rideID string) error {
	// Read the ride first: once released it's no longer this driver's.
	before, findErr := s.store.FindByID(ctx, rideID)
	if err := s.store.Release(ctx, rideID, driverID); err != nil {
		return err
	}
	slog.InfoContext(ctx, "ride released", "driverId", driverID, "rideId", rideID)
	if s.alerts != nil && findErr == nil {
		if _, plan, ok := toDriverRide(before, false); ok {
			s.alerts.DriverReleased(ctx, before.Booking, plan, driverID)
		}
	}
	return nil
}

// RateCustomer records the stars driverID gives the customer of their
// completed ride, once, and returns the ride.
func (s *DriverRideService) RateCustomer(ctx context.Context, driverID, rideID string, stars int, note string) (domain.DriverRide, error) {
	rating, err := newRating(stars, note)
	if err != nil {
		return domain.DriverRide{}, err
	}
	err = s.store.RateCustomer(ctx, rideID, driverID, rating)
	if errors.Is(err, repository.ErrRideStateConflict) {
		return domain.DriverRide{}, ErrCannotRateRide
	}
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "customer rated", "driverId", driverID, "rideId", rideID, "stars", stars)
	rb, err := s.store.FindByID(ctx, rideID)
	if err != nil {
		return domain.DriverRide{}, err
	}
	ride, _ := s.assigned(rb)
	return ride, nil
}

// ShareLocation records where driverID is, for the live map of any customer
// whose ride they're on the way to or driving. The app sends it only within
// a ride's tracking window, and customers can only read it within theirs
// (see BookingService.DriverLocation). It doesn't put the driver online.
func (s *DriverRideService) ShareLocation(ctx context.Context, driverID string, lat, lng float64, heading *float64) error {
	loc, err := newLiveLocation(lat, lng, heading, s.now())
	if err != nil {
		return err
	}
	s.live.Put(driverID, loc)
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
// offline in the live presence index, and — with a duty store — on their
// row in PostgreSQL, so a restart remembers. Going online requires cleared
// KYC. The app calls it every 20 s while on duty, as its heartbeat.
func (s *DriverRideService) SetDuty(ctx context.Context, driverID string, online bool, at *LatLng) error {
	if !online {
		s.presence.Remove(driverID)
		if s.duty != nil {
			if err := s.duty.EndDuty(ctx, driverID); err != nil {
				slog.WarnContext(ctx, "duty: saving off duty failed", "driverId", driverID, "error", err)
			}
		}
		return nil
	}
	if _, err := s.clearedProfile(ctx, driverID); err != nil {
		return err
	}
	s.presence.Register(domain.Driver{ID: driverID, Status: domain.DriverStatusAvailable})
	if at != nil {
		if err := s.presence.UpdateLocation(driverID, domain.Location{Lat: at.Lat, Lng: at.Lng}); err != nil {
			return err
		}
	}
	// Presence is what alerts read; the row is for after a restart, so a
	// failed write is logged rather than failing the heartbeat.
	if s.duty != nil {
		var lat, lng *float64
		if at != nil {
			lat, lng = &at.Lat, &at.Lng
		}
		if err := s.duty.SaveDuty(ctx, driverID, s.now(), lat, lng); err != nil {
			slog.WarnContext(ctx, "duty: saving on duty failed", "driverId", driverID, "error", err)
		}
	}
	return nil
}

// SetDutyStore has SetDuty keep duty in PostgreSQL as well as in presence.
func (s *DriverRideService) SetDutyStore(d DutyStore) { s.duty = d }

// advance moves driverID's ride from one status to the next. It is
// replay-safe: asking for the status the ride is already in returns the
// ride, without telling the customer a second time.
func (s *DriverRideService) advance(ctx context.Context, driverID, rideID string, from, to domain.RideStatus) (domain.DriverRide, error) {
	rb, err := s.store.Advance(ctx, rideID, driverID, from, to, s.now())
	if errors.Is(err, repository.ErrRideStateConflict) {
		if now, ferr := s.store.FindByID(ctx, rideID); ferr == nil &&
			now.Booking.DriverID == driverID && now.Booking.Status == to {
			slog.InfoContext(ctx, "ride step replayed", "driverId", driverID, "rideId", rideID, "status", to)
			ride, _ := s.assigned(now)
			return ride, nil
		}
	}
	if err != nil {
		return domain.DriverRide{}, err
	}
	slog.InfoContext(ctx, "ride advanced", "driverId", driverID, "rideId", rideID, "status", to)
	ride, _ := s.assigned(rb)
	if to == domain.RideStatusArrived && s.alerts != nil {
		s.alerts.DriverArrived(ctx, rb.Booking.UserID, driverID, ride)
	}
	if to == domain.RideStatusCompleted && s.alerts != nil {
		s.alerts.RideCompleted(ctx, rb.Booking.UserID, ride)
	}
	return ride, nil
}

// newStartOTP draws a uniformly random 4-digit code from crypto/rand.
func newStartOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(10_000))
	if err != nil {
		return "", fmt.Errorf("drawing start code: %w", err)
	}
	return fmt.Sprintf("%04d", n.Int64()), nil
}

// clearedProfile returns driverID's profile if their KYC lets them drive
// (see clearedToDrive).
func (s *DriverRideService) clearedProfile(ctx context.Context, driverID string) (domain.DriverProfile, error) {
	p, err := s.profiles.FindProfile(ctx, driverID)
	if err != nil {
		return domain.DriverProfile{}, err
	}
	if err := clearedToDrive(p, s.now()); err != nil {
		return domain.DriverProfile{}, err
	}
	return p, nil
}

// clearedToDrive says why p may not drive at now, or nil: their KYC must be
// verified (automatically on submission, or by a reviewer) and their
// licence, when its expiry is on record, not past it. Licences expire long
// after the one-off check at verification, so this is asked every time.
func clearedToDrive(p domain.DriverProfile, now time.Time) error {
	if p.KYCStatus != domain.KYCVerified {
		return ErrDriverNotCleared
	}
	n := now.In(ist)
	today := time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
	if v := p.LicenseValidUntil; v != nil && v.Before(today) {
		return fmt.Errorf("%w: your driving licence expired on %s; renew it and verify it again",
			ErrDriverNotCleared, v.Format("2 Jan 2006"))
	}
	return nil
}

// ReleaseHeldRides hands back every ride driverID has accepted but not
// started, as if they had released each — the customer is told and other
// drivers alerted while it's still open. Called when a reviewer takes the
// driver off the road. A ride already underway is left to finish. It
// returns how many were released.
func (s *DriverRideService) ReleaseHeldRides(ctx context.Context, driverID string) (int, error) {
	mine, err := s.store.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return 0, err
	}
	released := 0
	var errs []error
	for _, rb := range mine {
		switch rb.Booking.Status {
		case domain.RideStatusAccepted, domain.RideStatusArrived:
			if err := s.Release(ctx, driverID, rb.Booking.ID); err != nil {
				errs = append(errs, fmt.Errorf("releasing ride %s: %w", rb.Booking.ID, err))
				continue
			}
			released++
		case domain.RideStatusInProgress:
			slog.WarnContext(ctx, "ride left with a driver who lost clearance: already underway",
				"driverId", driverID, "rideId", rb.Booking.ID)
		}
	}
	return released, errors.Join(errs...)
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
		CancelledAt:      b.CancelledAt,
		CancelledBy:      b.CancelledBy,
		CancelReason:     b.CancelReason,
		NoShowAt:         noShowAt(b),
		MyRating:         b.CustomerRating,
		PaymentStatus:    b.PaymentStatus(),
		PaidAt:           b.PaidAt,

		CancellationFeePaise: b.CancellationFeePaise,
		BookedFarePaise:      b.BookedFarePaise,
	}
	if b.PaidAt != nil {
		ride.SharePaise = b.PaidPaise - b.CommissionPaise
	}
	if !withCustomer {
		// Not the driver's ride (yet): where, roughly, and no one to call.
		return coarseRide(ride), plan, true
	}
	c := rb.Customer
	ride.Customer = &c
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

// heldBy returns rb as its driver sees it when driverID holds it — accepted,
// at the pickup or underway.
func (s *DriverRideService) heldBy(rb domain.RideBooking, driverID string) (domain.DriverRide, bool) {
	if rb.Booking.DriverID != driverID || !holdsDriver(rb.Booking.Status) {
		return domain.DriverRide{}, false
	}
	return s.assigned(rb)
}

// assigned renders rb for the driver it's assigned to: every detail, and
// the customer — whose number goes once the ride has been over for
// contactLifetime. ok is false for unreadable details.
func (s *DriverRideService) assigned(rb domain.RideBooking) (domain.DriverRide, bool) {
	ride, _, ok := toDriverRide(rb, true)
	if ok && ride.Customer != nil && contactExpired(rb.Booking, s.now()) {
		ride.Customer.PhoneE164 = ""
	}
	return ride, ok
}

// contactLifetime is how long after a ride is completed or cancelled each
// side still sees the other's phone number: enough for a forgotten bag or
// a question about the bill, not for booking each other off the app.
const contactLifetime = 2 * time.Hour

// contactExpired reports whether, at now, b ended (completed or cancelled)
// more than contactLifetime ago.
func contactExpired(b domain.Booking, now time.Time) bool {
	ended := b.CompletedAt
	if ended == nil {
		ended = b.CancelledAt
	}
	return ended != nil && !now.Before(ended.Add(contactLifetime))
}

// holdsDriver reports whether a ride in status s still occupies its driver.
func holdsDriver(s domain.RideStatus) bool {
	return s == domain.RideStatusAccepted || s == domain.RideStatusArrived || s == domain.RideStatusInProgress
}

// overlaps reports whether two rides, each padded by rideGap, share any time.
func overlaps(a, b tripPlan) bool {
	return a.ScheduledAt.Before(b.EndsAt().Add(rideGap)) && b.ScheduledAt.Before(a.EndsAt().Add(rideGap))
}
