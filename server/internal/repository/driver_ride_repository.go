package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// ErrRideNotFound is returned when no booking has the given id (including an
// id that isn't a UUID at all).
var ErrRideNotFound = errors.New("ride not found")

// ErrRideUnavailable is returned when a driver tries to accept a ride that is
// no longer open — usually because another driver took it first.
var ErrRideUnavailable = errors.New("this ride is no longer available")

// ErrRideStateConflict is returned when a ride isn't assigned to the driver,
// or isn't at the step the requested change follows from (e.g. completing a
// ride that hasn't started).
var ErrRideStateConflict = errors.New("this ride can't make that change right now")

// SQLSTATEs mapped to ErrRideNotFound: a malformed UUID in the path, and a
// decline naming a booking that doesn't exist.
const (
	invalidTextRepresentation = "22P02"
	foreignKeyViolation       = "23503"
)

// bookingColumns is the shared SELECT/RETURNING list, in scanBooking's order.
const bookingColumns = `id, user_id, trip_type, details, created_at, status,
	coalesce(driver_id::text, ''), scheduled_at, fare_paise, fare_estimated,
	accepted_at, arrived_at, started_at, completed_at, coalesce(start_otp, '')`

// rideColumns is bookingColumns read through the `b` alias, plus the
// customer's name and phone from `u` — the shape scanRide reads.
const rideColumns = `b.id, b.user_id, b.trip_type, b.details, b.created_at, b.status,
	coalesce(b.driver_id::text, ''), b.scheduled_at, b.fare_paise, b.fare_estimated,
	b.accepted_at, b.arrived_at, b.started_at, b.completed_at, coalesce(b.start_otp, ''),
	u.name, u.phone_e164`

// timestampColumn is the column each forward status stamps.
var timestampColumn = map[domain.RideStatus]string{
	domain.RideStatusArrived:    "arrived_at",
	domain.RideStatusInProgress: "started_at",
	domain.RideStatusCompleted:  "completed_at",
}

// DriverRideRepository reads and moves bookings through the driver-side ride
// lifecycle. Every state change is a single conditional UPDATE, so two
// drivers racing for the same ride can't both win.
type DriverRideRepository struct {
	pool *pgxpool.Pool
}

// NewDriverRideRepository wires the repository to a connection pool.
func NewDriverRideRepository(pool *pgxpool.Pool) *DriverRideRepository {
	return &DriverRideRepository{pool: pool}
}

// ListOpen returns unassigned rides scheduled at or after from, soonest
// first, leaving out any driverID has declined.
func (r *DriverRideRepository) ListOpen(ctx context.Context, driverID string, from time.Time, limit int) ([]domain.RideBooking, error) {
	q := `
		SELECT ` + rideColumns + `
		FROM bookings b JOIN users u ON u.id = b.user_id
		WHERE b.status = 'requested'
		  AND b.scheduled_at >= $2
		  AND NOT EXISTS (
		      SELECT 1 FROM booking_declines d
		      WHERE d.booking_id = b.id AND d.driver_id = $1)
		ORDER BY b.scheduled_at
		LIMIT $3`
	return r.queryRides(ctx, q, driverID, from, limit)
}

// ListForDriver returns the rides assigned to driverID, latest scheduled
// first.
func (r *DriverRideRepository) ListForDriver(ctx context.Context, driverID string, limit int) ([]domain.RideBooking, error) {
	q := `
		SELECT ` + rideColumns + `
		FROM bookings b JOIN users u ON u.id = b.user_id
		WHERE b.driver_id = $1
		ORDER BY b.scheduled_at DESC
		LIMIT $2`
	return r.queryRides(ctx, q, driverID, limit)
}

// FindByID returns one ride, or [ErrRideNotFound].
func (r *DriverRideRepository) FindByID(ctx context.Context, id string) (domain.RideBooking, error) {
	q := `
		SELECT ` + rideColumns + `
		FROM bookings b JOIN users u ON u.id = b.user_id
		WHERE b.id = $1`
	rb, err := scanRide(r.pool.QueryRow(ctx, q, id))
	if err != nil {
		return domain.RideBooking{}, rideErr(err, ErrRideNotFound, "finding ride")
	}
	return rb, nil
}

// Accept assigns an open ride to driverID, issuing startOTP as the code the
// customer will give them to start it. It succeeds for exactly one driver:
// anyone after the first gets [ErrRideUnavailable].
func (r *DriverRideRepository) Accept(ctx context.Context, id, driverID string, at time.Time, startOTP string) (domain.RideBooking, error) {
	q := `
		WITH b AS (
		    UPDATE bookings
		    SET status = 'accepted', driver_id = $2, accepted_at = $3, start_otp = $4
		    WHERE id = $1 AND status = 'requested' AND driver_id IS NULL
		    RETURNING *)
		SELECT ` + rideColumns + `
		FROM b JOIN users u ON u.id = b.user_id`
	rb, err := scanRide(r.pool.QueryRow(ctx, q, id, driverID, at, startOTP))
	if err != nil {
		return domain.RideBooking{}, rideErr(err, ErrRideUnavailable, "accepting ride")
	}
	return rb, nil
}

// Advance moves driverID's ride from one status to the next, stamping the
// new status's timestamp. [ErrRideStateConflict] if the ride isn't theirs or
// isn't at from.
func (r *DriverRideRepository) Advance(ctx context.Context, id, driverID string, from, to domain.RideStatus, at time.Time) (domain.RideBooking, error) {
	col, ok := timestampColumn[to]
	if !ok {
		return domain.RideBooking{}, fmt.Errorf("advancing ride: no timestamp for status %q", to)
	}
	q := `
		WITH b AS (
		    UPDATE bookings
		    SET status = $4, ` + col + ` = $5
		    WHERE id = $1 AND driver_id = $2 AND status = $3
		    RETURNING *)
		SELECT ` + rideColumns + `
		FROM b JOIN users u ON u.id = b.user_id`
	rb, err := scanRide(r.pool.QueryRow(ctx, q, id, driverID, from, to, at))
	if err != nil {
		return domain.RideBooking{}, rideErr(err, ErrRideStateConflict, "advancing ride")
	}
	return rb, nil
}

// Release hands an accepted (not yet started) ride back to the open pool and
// hides it from driverID's own feed, in one transaction.
func (r *DriverRideRepository) Release(ctx context.Context, id, driverID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("releasing ride: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after Commit

	tag, err := tx.Exec(ctx, `
		UPDATE bookings
		SET status = 'requested', driver_id = NULL, accepted_at = NULL, arrived_at = NULL,
		    start_otp = NULL
		WHERE id = $1 AND driver_id = $2 AND status IN ('accepted', 'arrived')`,
		id, driverID)
	if err != nil {
		return rideErr(err, ErrRideNotFound, "releasing ride")
	}
	if tag.RowsAffected() == 0 {
		return ErrRideStateConflict
	}
	if err := insertDecline(ctx, tx, id, driverID); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("releasing ride: %w", err)
	}
	return nil
}

// SetStartOTP replaces the start code of driverID's ride that is waiting to
// start — used after too many wrong attempts. [ErrRideStateConflict] if the
// ride isn't theirs or has already started.
func (r *DriverRideRepository) SetStartOTP(ctx context.Context, id, driverID, startOTP string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE bookings SET start_otp = $3
		WHERE id = $1 AND driver_id = $2 AND status IN ('accepted', 'arrived')`,
		id, driverID, startOTP)
	if err != nil {
		return rideErr(err, ErrRideNotFound, "resetting start code")
	}
	if tag.RowsAffected() == 0 {
		return ErrRideStateConflict
	}
	return nil
}

// Decline hides an open ride from driverID's feed. Declining twice is fine.
func (r *DriverRideRepository) Decline(ctx context.Context, id, driverID string) error {
	return insertDecline(ctx, r.pool, id, driverID)
}

// Earnings sums driverID's completed rides over all time and since each of
// the given window starts.
func (r *DriverRideRepository) Earnings(ctx context.Context, driverID string, today, week, month time.Time) (domain.DriverEarnings, error) {
	const q = `
		SELECT
		    coalesce(sum(fare_paise) FILTER (WHERE completed_at >= $2), 0),
		    count(*) FILTER (WHERE completed_at >= $2),
		    coalesce(sum(fare_paise) FILTER (WHERE completed_at >= $3), 0),
		    count(*) FILTER (WHERE completed_at >= $3),
		    coalesce(sum(fare_paise) FILTER (WHERE completed_at >= $4), 0),
		    count(*) FILTER (WHERE completed_at >= $4),
		    coalesce(sum(fare_paise), 0),
		    count(*)
		FROM bookings
		WHERE driver_id = $1 AND status = 'completed'`

	var e domain.DriverEarnings
	err := r.pool.QueryRow(ctx, q, driverID, today, week, month).Scan(
		&e.Today.FarePaise, &e.Today.Rides,
		&e.Week.FarePaise, &e.Week.Rides,
		&e.Month.FarePaise, &e.Month.Rides,
		&e.Total.FarePaise, &e.Total.Rides,
	)
	if err != nil {
		return domain.DriverEarnings{}, fmt.Errorf("summing earnings: %w", err)
	}
	return e, nil
}

// execer is what insertDecline needs from a pool or a transaction.
type execer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

func insertDecline(ctx context.Context, db execer, id, driverID string) error {
	_, err := db.Exec(ctx, `
		INSERT INTO booking_declines (booking_id, driver_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING`, id, driverID)
	if err != nil {
		return rideErr(err, ErrRideNotFound, "declining ride")
	}
	return nil
}

func (r *DriverRideRepository) queryRides(ctx context.Context, q string, args ...any) ([]domain.RideBooking, error) {
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("listing rides: %w", err)
	}
	defer rows.Close()

	var out []domain.RideBooking
	for rows.Next() {
		rb, err := scanRide(rows)
		if err != nil {
			return nil, fmt.Errorf("listing rides: %w", err)
		}
		out = append(out, rb)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("listing rides: %w", err)
	}
	return out, nil
}

// rideErr maps "no row" and a malformed or dangling booking id onto the
// caller's sentinel, wrapping anything else with what was being done.
func rideErr(err, noRow error, doing string) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return noRow
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) &&
		(pgErr.Code == invalidTextRepresentation || pgErr.Code == foreignKeyViolation) {
		return ErrRideNotFound
	}
	return fmt.Errorf("%s: %w", doing, err)
}

func scanBooking(row pgx.Row) (domain.Booking, error) {
	var b domain.Booking
	err := row.Scan(
		&b.ID, &b.UserID, &b.TripType, &b.Details, &b.CreatedAt, &b.Status,
		&b.DriverID, &b.ScheduledAt, &b.FarePaise, &b.FareEstimated,
		&b.AcceptedAt, &b.ArrivedAt, &b.StartedAt, &b.CompletedAt, &b.StartOTP,
	)
	return b, err
}

func scanRide(row pgx.Row) (domain.RideBooking, error) {
	var rb domain.RideBooking
	b := &rb.Booking
	err := row.Scan(
		&b.ID, &b.UserID, &b.TripType, &b.Details, &b.CreatedAt, &b.Status,
		&b.DriverID, &b.ScheduledAt, &b.FarePaise, &b.FareEstimated,
		&b.AcceptedAt, &b.ArrivedAt, &b.StartedAt, &b.CompletedAt, &b.StartOTP,
		&rb.Customer.Name, &rb.Customer.PhoneE164,
	)
	return rb, err
}
