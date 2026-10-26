package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
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

// ErrBookingNotFound is returned when the customer has no booking with the
// given id (including an id that isn't a UUID at all).
var ErrBookingNotFound = errors.New("booking not found")

// ErrBookingStateConflict is returned when a booking isn't at a step the
// requested change follows from — cancelling a ride that has started, or
// rating one that isn't completed or already is rated.
var ErrBookingStateConflict = errors.New("this booking can't make that change right now")

// userBookingColumns is bookingColumnsB plus the assigned driver's name and
// phone from `d`, their average rating from customers and their photo's
// version (a prefix of the selfie's hash) — the shape scanUserBooking reads.
const userBookingColumns = bookingColumnsB + `,
	d.name, d.phone_e164,
	(SELECT avg(x.driver_rating)::float8 FROM bookings x WHERE x.driver_id = b.driver_id),
	(SELECT count(x.driver_rating) FROM bookings x WHERE x.driver_id = b.driver_id),
	(SELECT left(dd.sha256, 12) FROM driver_documents dd
	 WHERE dd.driver_id = b.driver_id AND dd.kind = 'selfie')`

// ListForUser returns userID's bookings with their assigned drivers, latest
// scheduled first.
func (r *BookingRepository) ListForUser(ctx context.Context, userID string, limit int) ([]domain.UserBooking, error) {
	q := `
		SELECT ` + userBookingColumns + `
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
		ub, err := scanUserBooking(rows)
		if err != nil {
			return nil, fmt.Errorf("listing bookings: %w", err)
		}
		out = append(out, ub)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("listing bookings: %w", err)
	}
	return out, nil
}

// FindForUser returns userID's booking id with its assigned driver, or
// [ErrBookingNotFound].
func (r *BookingRepository) FindForUser(ctx context.Context, id, userID string) (domain.UserBooking, error) {
	q := `
		SELECT ` + userBookingColumns + `
		FROM bookings b LEFT JOIN drivers d ON d.id = b.driver_id
		WHERE b.id = $1 AND b.user_id = $2`
	ub, err := scanUserBooking(r.pool.QueryRow(ctx, q, id, userID))
	if err != nil {
		return domain.UserBooking{}, bookingErr(rideErr(err, ErrBookingNotFound, "finding booking"))
	}
	return ub, nil
}

// Cancel cancels userID's booking id for the customer, provided the trip
// hasn't started: it must still be requested, accepted or arrived. The
// driver stays on the row so their rides list shows it as cancelled; the
// start code is cleared. Returns the cancelled booking,
// [ErrBookingNotFound], or [ErrBookingStateConflict].
func (r *BookingRepository) Cancel(ctx context.Context, id, userID, reason string, at time.Time) (domain.Booking, error) {
	q := `
		UPDATE bookings
		SET status = 'cancelled', cancelled_at = $3, cancelled_by = $4,
		    cancel_reason = nullif($5, ''), start_otp = NULL
		WHERE id = $1 AND user_id = $2 AND status IN ('requested', 'accepted', 'arrived')
		RETURNING ` + bookingColumns
	b, err := scanBooking(r.pool.QueryRow(ctx, q, id, userID, at, domain.CancelledByCustomer, reason))
	if err != nil {
		return domain.Booking{}, r.whyUnchanged(ctx, err, id, userID, "cancelling booking")
	}
	return b, nil
}

// RateDriver records the stars userID gave the driver of their completed
// booking id, once. [ErrBookingNotFound], or [ErrBookingStateConflict] if
// it isn't completed or is already rated.
func (r *BookingRepository) RateDriver(ctx context.Context, id, userID string, rating domain.RideRating) error {
	q := `
		UPDATE bookings SET driver_rating = $3, driver_rating_note = nullif($4, '')
		WHERE id = $1 AND user_id = $2 AND status = 'completed'
		  AND driver_id IS NOT NULL AND driver_rating IS NULL
		RETURNING id`
	var got string
	if err := r.pool.QueryRow(ctx, q, id, userID, rating.Stars, rating.Note).Scan(&got); err != nil {
		return r.whyUnchanged(ctx, err, id, userID, "rating driver")
	}
	return nil
}

// whyUnchanged explains a conditional UPDATE that matched no row: the
// booking isn't the user's ([ErrBookingNotFound]) or isn't at the right step
// ([ErrBookingStateConflict]). Other errors are wrapped with doing.
func (r *BookingRepository) whyUnchanged(ctx context.Context, err error, id, userID, doing string) error {
	if !errors.Is(err, pgx.ErrNoRows) {
		return bookingErr(rideErr(err, ErrBookingNotFound, doing))
	}
	var exists bool
	if err := r.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM bookings WHERE id = $1 AND user_id = $2)`,
		id, userID).Scan(&exists); err != nil {
		return fmt.Errorf("%s: %w", doing, err)
	}
	if !exists {
		return ErrBookingNotFound
	}
	return ErrBookingStateConflict
}

// bookingErr reports a malformed booking id (which rideErr reads as a
// missing ride) as a missing booking.
func bookingErr(err error) error {
	if errors.Is(err, ErrRideNotFound) {
		return ErrBookingNotFound
	}
	return err
}

func scanUserBooking(row pgx.Row) (domain.UserBooking, error) {
	var (
		ub          domain.UserBooking
		name, phone *string
		average     *float64
		rated       int
		photo       *string
	)
	br := bookingRow{b: &ub.Booking}
	err := row.Scan(br.targets(&name, &phone, &average, &rated, &photo)...)
	br.finish()
	if name != nil && phone != nil {
		ub.Driver = &domain.RideDriver{Name: *name, PhoneE164: *phone, RatingCount: rated}
		if rated > 0 {
			ub.Driver.Rating = average
		}
		if photo != nil {
			ub.Driver.PhotoVersion = *photo
		}
	}
	return ub, err
}
