package service

import (
	"context"
	"errors"
	"log/slog"
	"strings"
)

// ErrInvalidBooking is returned when a submitted booking names no trip type or
// carries no details.
var ErrInvalidBooking = errors.New("booking tripType and details are required")

// BookingService receives confirmed bookings from the customer app.
//
// Matchmaking and persistence aren't built yet, so for now a booking is
// recorded in the server log at INFO with everything the app sent — enough to
// see live bookings arrive and to design the ride pipeline against real
// payloads. PostgreSQL becomes the source of truth when rides are persisted.
type BookingService struct{}

// NewBookingService builds the service. No dependencies yet; the constructor
// keeps the wiring shape stable for when a store and matchmaker arrive.
func NewBookingService() *BookingService {
	return &BookingService{}
}

// Record accepts userID's confirmed booking of the given tripType ("roundTrip",
// "oneWay", "multiStop") and logs its details.
func (s *BookingService) Record(ctx context.Context, userID, tripType string, details map[string]any) error {
	tripType = strings.TrimSpace(tripType)
	if tripType == "" || len(details) == 0 {
		return ErrInvalidBooking
	}
	slog.InfoContext(ctx, "booking confirmed",
		"userId", userID,
		"tripType", tripType,
		"details", details,
	)
	return nil
}
