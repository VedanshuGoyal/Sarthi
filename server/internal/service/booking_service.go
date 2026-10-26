package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// ErrInvalidBooking is returned when a submitted booking names no trip type or
// carries no details.
var ErrInvalidBooking = errors.New("booking tripType and details are required")

// ErrCannotCancel is returned when a customer cancels a ride that has
// already started, ended or been cancelled.
var ErrCannotCancel = fmt.Errorf("this ride has already started or ended, so it can't be cancelled: %w",
	repository.ErrBookingStateConflict)

// ErrCannotRate is returned when a customer rates a ride that isn't
// completed, or rates it twice.
var ErrCannotRate = fmt.Errorf("you can rate a ride once, after it's completed: %w",
	repository.ErrBookingStateConflict)

// ErrBookingTooSoon is returned when a booking starts too soon for a driver
// to accept it before it closes (see acceptCutoff).
var ErrBookingTooSoon = errors.New("pick a start time at least 45 minutes from now")

const (
	// acceptCutoff is how long before its start an open ride stops taking
	// drivers — the time a driver needs to reach the pickup. A ride nobody
	// took by then is reported to the customer as expired.
	acceptCutoff = 30 * time.Minute

	// minBookingLead is how far ahead a ride must be booked: the cutoff plus
	// a quarter hour for a driver to accept. The app offers no earlier slot.
	minBookingLead = 45 * time.Minute

	// bookingLeadSlack forgives the minutes a customer spends on the form
	// after picking the earliest slot.
	bookingLeadSlack = 5 * time.Minute

	// maxCancelReason caps the reason a customer gives for cancelling, in
	// characters; a longer one is cut.
	maxCancelReason = 200
)

// closedToDrivers reports whether an open ride starting at start can no
// longer be accepted at now.
func closedToDrivers(start, now time.Time) bool {
	return now.After(start.Add(-acceptCutoff))
}

// BookingStore is the slice of persistence this service needs. Defined
// consumer-side so the service stays testable with a fake.
type BookingStore interface {
	Insert(ctx context.Context, p repository.InsertBookingParams) (domain.Booking, error)
	ListForUser(ctx context.Context, userID string, limit int) ([]domain.UserBooking, error)
	FindForUser(ctx context.Context, id, userID string) (domain.UserBooking, error)
	Cancel(ctx context.Context, id, userID, reason string, at time.Time) (domain.Booking, error)
	RateDriver(ctx context.Context, id, userID string, rating domain.RideRating) error
}

// BookingAlerter tells drivers about bookings (NotifyService): a new ride
// request goes to those nearby, a cancelled ride to the driver who had it.
// Each call returns at once; the alerts go out in the background.
type BookingAlerter interface {
	RideRequested(ctx context.Context, b domain.Booking, plan tripPlan)
	RideCancelled(ctx context.Context, b domain.Booking, plan tripPlan)
}

// DriverLocator reads the positions drivers' apps share while on a ride
// (memstore.LiveLocations).
type DriverLocator interface {
	Latest(driverID string) (domain.LiveLocation, bool)
}

// DriverPhotos serves the small copy of a driver's selfie that customers see
// (DriverKYCService).
type DriverPhotos interface {
	OpenDriverPhoto(ctx context.Context, driverID string) ([]byte, string, error)
}

// maxCustomerBookings caps the customer's bookings list.
const maxCustomerBookings = 50

// BookingService runs the customer side of a booking's life: recording it,
// listing it with its driver and progress, cancelling it before the trip
// starts, rating the driver afterwards, and showing where the driver is
// while they're on the way.
//
// A recorded booking is an open ride request: drivers see it in their app's
// requests feed (see DriverRideService) until one accepts it. PostgreSQL is
// the source of truth.
type BookingService struct {
	store  BookingStore
	alerts BookingAlerter
	live   DriverLocator
	photos DriverPhotos
	now    func() time.Time
}

// NewBookingService wires the service to its store, the driver alerts sent
// for new and cancelled bookings (nil sends none), the drivers' shared
// positions (nil shows none) and their photos (nil shows none).
func NewBookingService(store BookingStore, alerts BookingAlerter, live DriverLocator, photos DriverPhotos) *BookingService {
	return &BookingService{store: store, alerts: alerts, live: live, photos: photos, now: time.Now}
}

// Record validates and persists userID's confirmed booking of the given
// tripType ("roundTrip", "oneWay", "multiStop"), returning the stored booking
// with the id the database assigned.
func (s *BookingService) Record(ctx context.Context, userID, tripType string, details map[string]any) (domain.Booking, error) {
	tripType = strings.TrimSpace(tripType)
	if tripType == "" || len(details) == 0 {
		return domain.Booking{}, ErrInvalidBooking
	}
	// Read the details now rather than when a driver lists them: a booking no
	// driver can read is one nobody will ever take.
	plan, err := parseTripPlan(tripType, details)
	if err != nil {
		return domain.Booking{}, fmt.Errorf("%w: %v", ErrInvalidBooking, err)
	}
	if plan.ScheduledAt.Before(s.now().Add(minBookingLead - bookingLeadSlack)) {
		return domain.Booking{}, ErrBookingTooSoon
	}
	fare, estimated := plan.Fare()
	booking, err := s.store.Insert(ctx, repository.InsertBookingParams{
		UserID:        userID,
		TripType:      tripType,
		Details:       details,
		ScheduledAt:   plan.ScheduledAt,
		FarePaise:     fare,
		FareEstimated: estimated,
	})
	if err != nil {
		return domain.Booking{}, err
	}
	slog.InfoContext(ctx, "booking confirmed",
		"bookingId", booking.ID,
		"userId", userID,
		"tripType", tripType,
	)
	if s.alerts != nil {
		s.alerts.RideRequested(ctx, booking, plan)
	}
	return booking, nil
}

// ListMine returns userID's bookings, latest scheduled first, each with its
// status, assigned driver and — while the driver is on the way or waiting at
// the pickup — the code the customer gives them to start the trip. A request
// no driver took before it closed is reported as expired. A booking whose
// details can't be read is skipped rather than failing the list.
func (s *BookingService) ListMine(ctx context.Context, userID string) ([]domain.CustomerBooking, error) {
	rows, err := s.store.ListForUser(ctx, userID, maxCustomerBookings)
	if err != nil {
		return nil, err
	}
	now := s.now()
	out := []domain.CustomerBooking{}
	for _, ub := range rows {
		if cb, ok := toCustomerBooking(ctx, ub, now); ok {
			out = append(out, cb)
		}
	}
	return out, nil
}

// Cancel cancels userID's booking before its trip starts, with the reason
// they picked (optional). A driver who had taken it is told, and is free to
// take other rides; their rides list keeps it, as cancelled.
func (s *BookingService) Cancel(ctx context.Context, userID, bookingID, reason string) (domain.CustomerBooking, error) {
	reason = strings.TrimSpace(reason)
	if r := []rune(reason); len(r) > maxCancelReason {
		reason = strings.TrimSpace(string(r[:maxCancelReason]))
	}
	b, err := s.store.Cancel(ctx, bookingID, userID, reason, s.now())
	if errors.Is(err, repository.ErrBookingStateConflict) {
		return domain.CustomerBooking{}, ErrCannotCancel
	}
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	slog.InfoContext(ctx, "booking cancelled by customer",
		"bookingId", b.ID, "userId", userID, "driverId", b.DriverID)
	if b.DriverID != "" && s.alerts != nil {
		if plan, err := planOf(b); err == nil {
			s.alerts.RideCancelled(ctx, b, plan)
		}
	}
	return s.mine(ctx, userID, bookingID)
}

// RateDriver records the stars userID gives the driver of their completed
// booking, once.
func (s *BookingService) RateDriver(ctx context.Context, userID, bookingID string, stars int, note string) (domain.CustomerBooking, error) {
	rating, err := newRating(stars, note)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	err = s.store.RateDriver(ctx, bookingID, userID, rating)
	if errors.Is(err, repository.ErrBookingStateConflict) {
		return domain.CustomerBooking{}, ErrCannotRate
	}
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	slog.InfoContext(ctx, "driver rated", "bookingId", bookingID, "userId", userID, "stars", stars)
	return s.mine(ctx, userID, bookingID)
}

// DriverPhoto returns the photo of the driver assigned to userID's booking,
// and its version (see [domain.RideDriver.PhotoVersion]). [ErrNoDriverPhoto]
// when no driver has accepted it or they have no photo.
func (s *BookingService) DriverPhoto(ctx context.Context, userID, bookingID string) ([]byte, string, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return nil, "", err
	}
	if ub.Booking.DriverID == "" || s.photos == nil {
		return nil, "", ErrNoDriverPhoto
	}
	return s.photos.OpenDriverPhoto(ctx, ub.Booking.DriverID)
}

// DriverLocation returns where the driver of userID's booking last said they
// were, while the ride is in its live-tracking window (see sharesLocation) —
// nil if they haven't shared a position within liveFixMaxAge.
// [ErrNotTracking] outside the window.
func (s *BookingService) DriverLocation(ctx context.Context, userID, bookingID string) (*domain.LiveLocation, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return nil, err
	}
	b := ub.Booking
	plan, err := planOf(b)
	now := s.now()
	if err != nil || b.DriverID == "" || !sharesLocation(b.Status, plan.ScheduledAt, now) {
		return nil, ErrNotTracking
	}
	if s.live == nil {
		return nil, nil
	}
	loc, ok := s.live.Latest(b.DriverID)
	if !ok || now.Sub(loc.UpdatedAt) > liveFixMaxAge {
		return nil, nil
	}
	return &loc, nil
}

// Get returns one of userID's bookings as the customer app shows it.
func (s *BookingService) Get(ctx context.Context, userID, bookingID string) (domain.CustomerBooking, error) {
	return s.mine(ctx, userID, bookingID)
}

// mine re-reads one of userID's bookings as the customer app shows it.
func (s *BookingService) mine(ctx context.Context, userID, bookingID string) (domain.CustomerBooking, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	cb, ok := toCustomerBooking(ctx, ub, s.now())
	if !ok {
		return domain.CustomerBooking{}, fmt.Errorf("booking %s: unreadable details", bookingID)
	}
	return cb, nil
}

// planOf reads a stored booking's details, with the start time the server
// recorded taking precedence over the one in them.
func planOf(b domain.Booking) (tripPlan, error) {
	plan, err := parseTripPlan(b.TripType, b.Details)
	if err != nil {
		return tripPlan{}, err
	}
	if b.ScheduledAt != nil {
		plan.ScheduledAt = *b.ScheduledAt
	}
	return plan, nil
}

// toCustomerBooking renders a stored booking for the customer app. ok is
// false for one whose details can't be read.
func toCustomerBooking(ctx context.Context, ub domain.UserBooking, now time.Time) (domain.CustomerBooking, bool) {
	b := ub.Booking
	plan, err := planOf(b)
	if err != nil {
		slog.WarnContext(ctx, "booking skipped: unreadable details", "bookingId", b.ID, "error", err)
		return domain.CustomerBooking{}, false
	}
	fare, estimated := b.FarePaise, b.FareEstimated
	if fare == 0 {
		fare, estimated = plan.Fare()
	}
	cb := domain.CustomerBooking{
		ID:               b.ID,
		TripType:         b.TripType,
		Status:           b.Status,
		ScheduledAt:      plan.ScheduledAt,
		EndsAt:           plan.EndsAt(),
		FarePaise:        fare,
		FareEstimated:    estimated,
		Pickup:           plan.Pickup,
		Destination:      plan.Destination,
		StopCount:        len(plan.Stops),
		Stops:            plan.Stops,
		Hours:            plan.Hours,
		EstimatedMinutes: plan.EstimatedMinutes,
		Car:              plan.Car,
		Driver:           ub.Driver,
		CreatedAt:        b.CreatedAt,
		AcceptedAt:       b.AcceptedAt,
		ArrivedAt:        b.ArrivedAt,
		StartedAt:        b.StartedAt,
		CompletedAt:      b.CompletedAt,
		CancelledAt:      b.CancelledAt,
		CancelledBy:      b.CancelledBy,
		CancelReason:     b.CancelReason,
		MyRating:         b.DriverRating,
		PaidAt:           b.PaidAt,
	}
	// Paid out is the driver's business; to the customer it's just paid.
	switch b.PaymentStatus() {
	case domain.RidePaymentDue:
		cb.PaymentStatus = domain.RidePaymentDue
	case domain.RidePaymentPaid, domain.RidePaymentPaidOut:
		cb.PaymentStatus = domain.RidePaymentPaid
	}
	if b.Status == domain.RideStatusAccepted || b.Status == domain.RideStatusArrived {
		cb.StartOTP = b.StartOTP
	}
	if b.Status == domain.RideStatusRequested && closedToDrivers(plan.ScheduledAt, now) {
		cb.Status = domain.RideStatusExpired
	}
	return cb, true
}
