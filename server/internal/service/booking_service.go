package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// ErrInvalidBooking is returned when a submitted booking names no trip type or
// carries no details.
var ErrInvalidBooking = errors.New("booking tripType and details are required")

// BookingStore is the slice of persistence this service needs. Defined
// consumer-side so the service stays testable with a fake.
type BookingStore interface {
	Insert(ctx context.Context, p repository.InsertBookingParams) (domain.Booking, error)
	ListForUser(ctx context.Context, userID string, limit int) ([]domain.UserBooking, error)
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
	store BookingStore
}

// NewBookingService wires the service to its store.
func NewBookingService(store BookingStore) *BookingService {
	return &BookingService{store: store}
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
	return booking, nil
}

// ListMine returns userID's bookings, latest scheduled first, each with its
// status, assigned driver and — while the driver is on the way or waiting at
// the pickup — the code the customer gives them to start the trip. A booking
// whose details can't be read is skipped rather than failing the list.
func (s *BookingService) ListMine(ctx context.Context, userID string) ([]domain.CustomerBooking, error) {
	rows, err := s.store.ListForUser(ctx, userID, maxCustomerBookings)
	if err != nil {
		return nil, err
	}
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
		out = append(out, cb)
	}
	return out, nil
}
