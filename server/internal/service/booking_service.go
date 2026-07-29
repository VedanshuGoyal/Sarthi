package service

import (
	"context"
	"errors"
	"log/slog"
	"strings"

	"github.com/sarthi/server/internal/domain"
)

// ErrInvalidBooking is returned when a submitted booking names no trip type or
// carries no details.
var ErrInvalidBooking = errors.New("booking tripType and details are required")

// BookingStore is the slice of persistence this service needs. Defined
// consumer-side so the service stays testable with a fake.
type BookingStore interface {
	Insert(ctx context.Context, userID, tripType string, details map[string]any) (domain.Booking, error)
}

// BookingService receives confirmed bookings from the customer app and persists
// them.
//
// Matchmaking isn't built yet, so a booking is stored and logged — enough to be
// the source of truth for what a customer asked for and to design the ride
// pipeline against real payloads. PostgreSQL is that source of truth.
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
	booking, err := s.store.Insert(ctx, userID, tripType, details)
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
