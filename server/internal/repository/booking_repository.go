package repository

import (
	"context"
	"fmt"

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

// Insert records the user's booking and returns the stored row, with the id and
// created_at the database assigned. details is written verbatim as JSONB —
// pgx marshals the map on the way in and unmarshals it back on the way out.
func (r *BookingRepository) Insert(ctx context.Context, userID, tripType string, details map[string]any) (domain.Booking, error) {
	const q = `
		INSERT INTO bookings (user_id, trip_type, details)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, trip_type, details, created_at`

	var b domain.Booking
	err := r.pool.QueryRow(ctx, q, userID, tripType, details).
		Scan(&b.ID, &b.UserID, &b.TripType, &b.Details, &b.CreatedAt)
	if err != nil {
		return domain.Booking{}, fmt.Errorf("inserting booking: %w", err)
	}
	return b, nil
}
