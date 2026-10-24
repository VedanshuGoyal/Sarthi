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
}

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
