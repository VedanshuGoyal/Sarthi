package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// BookingRepository persists confirmed bookings submitted from the customer app.
type BookingRepository struct {
	pool *pgxpool.Pool
}

// NewBookingRepository wires the repository to a connection pool.
func NewBookingRepository(pool *pgxpool.Pool) *BookingRepository {
	return &BookingRepository{pool: pool}
}

// InsertBookingParams is a new booking: what the customer sent, plus the
// start time and fare the service read out of it.
type InsertBookingParams struct {
	UserID        string
	TripType      string
	Details       map[string]any
	ScheduledAt   time.Time
	FarePaise     int64
	FareEstimated bool
}

// Insert records the user's booking as an open ride request and returns the
// stored row, with the id and created_at the database assigned. Details is
// written verbatim as JSONB — pgx marshals the map on the way in and
// unmarshals it back on the way out.
func (r *BookingRepository) Insert(ctx context.Context, p InsertBookingParams) (domain.Booking, error) {
	q := `
		INSERT INTO bookings (user_id, trip_type, details, scheduled_at, fare_paise, fare_estimated)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING ` + bookingColumns

	b, err := scanBooking(r.pool.QueryRow(ctx, q,
		p.UserID, p.TripType, p.Details, p.ScheduledAt, p.FarePaise, p.FareEstimated))
	if err != nil {
		return domain.Booking{}, fmt.Errorf("inserting booking: %w", err)
	}
	return b, nil
}
