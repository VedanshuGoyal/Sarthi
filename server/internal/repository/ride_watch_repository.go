package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// RideWatchRepository serves the ride watchdog: the bookings due a check,
// and the booking_events rows that record each check was made, once.
type RideWatchRepository struct {
	db DB
}

// NewRideWatchRepository wires the repository to a pool (or a transaction).
func NewRideWatchRepository(db DB) *RideWatchRepository {
	return &RideWatchRepository{db: db}
}

// Unmarked returns up to limit bookings in status whose start is after from
// and at or before to, soonest first, that have no kind event yet.
func (r *RideWatchRepository) Unmarked(ctx context.Context, kind string, status domain.RideStatus, from, to time.Time, limit int) ([]domain.Booking, error) {
	q := `
		SELECT ` + bookingColumnsB + `
		FROM bookings b
		WHERE b.status = $1 AND b.scheduled_at > $2 AND b.scheduled_at <= $3
		  AND NOT EXISTS (
		      SELECT 1 FROM booking_events e WHERE e.booking_id = b.id AND e.kind = $4)
		ORDER BY b.scheduled_at
		LIMIT $5`
	rows, err := r.db.Query(ctx, q, status, from, to, kind, limit)
	if err != nil {
		return nil, fmt.Errorf("listing bookings due %s: %w", kind, err)
	}
	defer rows.Close()
	var out []domain.Booking
	for rows.Next() {
		b, err := scanBooking(rows)
		if err != nil {
			return nil, fmt.Errorf("listing bookings due %s: %w", kind, err)
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("listing bookings due %s: %w", kind, err)
	}
	return out, nil
}

// Mark records that kind happened to bookingID at at. It reports false when
// the booking already had a kind event — someone else got there first — so
// a caller acts only on true.
func (r *RideWatchRepository) Mark(ctx context.Context, bookingID, kind string, at time.Time) (bool, error) {
	tag, err := r.db.Exec(ctx, `
		INSERT INTO booking_events (booking_id, kind, created_at) VALUES ($1, $2, $3)
		ON CONFLICT (booking_id, kind) DO NOTHING`, bookingID, kind, at)
	if err != nil {
		return false, rideErr(err, ErrRideNotFound, "recording booking event")
	}
	return tag.RowsAffected() == 1, nil
}
