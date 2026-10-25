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
}

// RequestAlerter tells nearby drivers about a new ride request
// (NotifyService). It returns at once; the alerts go out in the background.
type RequestAlerter interface {
	RideRequested(ctx context.Context, b domain.Booking, plan tripPlan)
}

// maxCustomerBookings caps the customer's bookings list.
const maxCustomerBookings = 50

// BookingService receives confirmed bookings from the customer app and persists
// them.
//
// A recorded booking is an open ride request: drivers see it in their app's
// requests feed (see DriverRideService) until one accepts it. PostgreSQL is
// the source of truth.
type BookingService struct {
	store  BookingStore
	alerts RequestAlerter
	now    func() time.Time
}

// NewBookingService wires the service to its store and to the driver alerts
// sent for each new booking (nil sends none).
func NewBookingService(store BookingStore, alerts RequestAlerter) *BookingService {
	return &BookingService{store: store, alerts: alerts, now: time.Now}
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
		b := ub.Booking
		plan, err := parseTripPlan(b.TripType, b.Details)
		if err != nil {
			slog.WarnContext(ctx, "booking skipped: unreadable details", "bookingId", b.ID, "error", err)
			continue
		}
		if b.ScheduledAt != nil {
			plan.ScheduledAt = *b.ScheduledAt
		}
		fare, estimated := b.FarePaise, b.FareEstimated
		if fare == 0 {
			fare, estimated = plan.Fare()
		}
		cb := domain.CustomerBooking{
			ID:            b.ID,
			TripType:      b.TripType,
			Status:        b.Status,
			ScheduledAt:   plan.ScheduledAt,
			EndsAt:        plan.EndsAt(),
			FarePaise:     fare,
			FareEstimated: estimated,
			Pickup:        plan.Pickup,
			Destination:   plan.Destination,
			StopCount:     len(plan.Stops),
			Car:           plan.Car,
			Driver:        ub.Driver,
			CreatedAt:     b.CreatedAt,
		}
		if b.Status == domain.RideStatusAccepted || b.Status == domain.RideStatusArrived {
			cb.StartOTP = b.StartOTP
		}
		if b.Status == domain.RideStatusRequested && closedToDrivers(plan.ScheduledAt, now) {
			cb.Status = domain.RideStatusExpired
		}
		out = append(out, cb)
	}
	return out, nil
}
