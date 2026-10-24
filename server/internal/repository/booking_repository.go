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

// ListForUser returns userID's bookings with their assigned drivers, latest
// scheduled first.
func (r *BookingRepository) ListForUser(ctx context.Context, userID string, limit int) ([]domain.UserBooking, error) {
	const q = `
		SELECT b.id, b.user_id, b.trip_type, b.details, b.created_at, b.status,
		       coalesce(b.driver_id::text, ''), b.scheduled_at, b.fare_paise, b.fare_estimated,
		       b.accepted_at, b.arrived_at, b.started_at, b.completed_at, coalesce(b.start_otp, ''),
		       d.name, d.phone_e164
		FROM bookings b LEFT JOIN drivers d ON d.id = b.driver_id
		WHERE b.user_id = $1
		ORDER BY b.scheduled_at DESC NULLS LAST, b.created_at DESC
		LIMIT $2`

	rows, err := r.pool.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("listing bookings: %w", err)
	}
	defer rows.Close()

	var out []domain.UserBooking
	for rows.Next() {
		var (
			ub          domain.UserBooking
			name, phone *string
		)
		b := &ub.Booking
		if err := rows.Scan(
			&b.ID, &b.UserID, &b.TripType, &b.Details, &b.CreatedAt, &b.Status,
			&b.DriverID, &b.ScheduledAt, &b.FarePaise, &b.FareEstimated,
			&b.AcceptedAt, &b.ArrivedAt, &b.StartedAt, &b.CompletedAt, &b.StartOTP,
			&name, &phone,
		); err != nil {
			return nil, fmt.Errorf("listing bookings: %w", err)
		}
		if name != nil && phone != nil {
			ub.Driver = &domain.RideDriver{Name: *name, PhoneE164: *phone}
		}
		out = append(out, ub)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("listing bookings: %w", err)
	}
	return out, nil
}
