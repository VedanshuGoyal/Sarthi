package repository

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// BookingRepository persists confirmed bookings submitted from the customer app.
type BookingRepository struct {
	db DB
}

// NewBookingRepository wires the repository to a pool (or a transaction).
func NewBookingRepository(db DB) *BookingRepository {
	return &BookingRepository{db: db}
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

	// IdempotencyKey is the app's key for this booking attempt, "" for none:
	// a booking the user already made with it is returned instead.
	IdempotencyKey string
	// DuplicateSince, when set, also returns instead of inserting the user's
	// booking created since then for the same trip type, start and details
	// that hasn't been cancelled — a retry from an app that sends no key.
	DuplicateSince time.Time
}

// Insert records the user's booking as an open ride request and returns the
// stored row, with the id and created_at the database assigned — or, when
// p names a booking already made (see IdempotencyKey and DuplicateSince),
// that one, with existing true. Details is written verbatim as JSONB — pgx
// marshals the map on the way in and unmarshals it back on the way out.
//
// The look-up and the insert run under a per-customer lock, so two copies
// of one submit racing in can't both miss each other.
func (r *BookingRepository) Insert(ctx context.Context, p InsertBookingParams) (b domain.Booking, existing bool, err error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return domain.Booking{}, false, fmt.Errorf("inserting booking: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
		"booking-insert:"+p.UserID); err != nil {
		return domain.Booking{}, false, fmt.Errorf("inserting booking: %w", err)
	}
	b, existing, err = findRepeat(ctx, tx, p)
	if err != nil {
		return domain.Booking{}, false, err
	}
	if !existing {
		b, err = scanBooking(tx.QueryRow(ctx, `
			INSERT INTO bookings
			    (user_id, trip_type, details, scheduled_at, fare_paise, fare_estimated, idempotency_key)
			VALUES ($1, $2, $3, $4, $5, $6, nullif($7, ''))
			RETURNING `+bookingColumns,
			p.UserID, p.TripType, p.Details, p.ScheduledAt, p.FarePaise, p.FareEstimated, p.IdempotencyKey))
		if err != nil {
			return domain.Booking{}, false, fmt.Errorf("inserting booking: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.Booking{}, false, fmt.Errorf("inserting booking: %w", err)
	}
	return b, existing, nil
}

// findRepeat looks for the booking p repeats: the user's booking made with
// the same idempotency key, else (when p.DuplicateSince is set) their
// latest uncancelled one since then with the same trip type, start and
// details. JSONB equality ignores key order and spacing.
func findRepeat(ctx context.Context, tx pgx.Tx, p InsertBookingParams) (domain.Booking, bool, error) {
	if p.IdempotencyKey != "" {
		b, err := scanBooking(tx.QueryRow(ctx, `
			SELECT `+bookingColumns+` FROM bookings
			WHERE user_id = $1 AND idempotency_key = $2`, p.UserID, p.IdempotencyKey))
		if err == nil {
			return b, true, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return domain.Booking{}, false, fmt.Errorf("finding booking by key: %w", err)
		}
	}
	if p.DuplicateSince.IsZero() {
		return domain.Booking{}, false, nil
	}
	b, err := scanBooking(tx.QueryRow(ctx, `
		SELECT `+bookingColumns+` FROM bookings
		WHERE user_id = $1 AND trip_type = $2 AND scheduled_at = $3 AND details = $4
		  AND created_at >= $5 AND status <> 'cancelled'
		ORDER BY created_at DESC
		LIMIT 1`, p.UserID, p.TripType, p.ScheduledAt, p.Details, p.DuplicateSince))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Booking{}, false, nil
	}
	if err != nil {
		return domain.Booking{}, false, fmt.Errorf("finding a repeated booking: %w", err)
	}
	return b, true, nil
}

// UnpaidDues lists what userID still owes for — completed rides and
// cancellation fees not yet paid — oldest first. Each is collected with the
// customer's next payment.
func (r *BookingRepository) UnpaidDues(ctx context.Context, userID string) ([]domain.Due, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id::text, `+owedPaise+`
		FROM bookings
		WHERE user_id = $1 AND paid_at IS NULL
		  AND ((status = 'completed' AND fare_paise > 0)
		       OR (status = 'cancelled' AND cancellation_fee_paise IS NOT NULL))
		ORDER BY coalesce(completed_at, cancelled_at) NULLS FIRST, created_at, id`, userID)
	if err != nil {
		return nil, fmt.Errorf("listing unpaid dues: %w", err)
	}
	defer rows.Close()
	var out []domain.Due
	for rows.Next() {
		var d domain.Due
		if err := rows.Scan(&d.BookingID, &d.AmountPaise); err != nil {
			return nil, fmt.Errorf("listing unpaid dues: %w", err)
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// DriverBusyElsewhere reports whether driverID is at the pickup of, or
// driving, a ride other than bookingID.
func (r *BookingRepository) DriverBusyElsewhere(ctx context.Context, driverID, bookingID string) (bool, error) {
	var busy bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS (
		    SELECT 1 FROM bookings
		    WHERE driver_id = $1 AND id <> $2 AND status IN ('arrived', 'in_progress'))`,
		driverID, bookingID).Scan(&busy)
	if err != nil {
		return false, fmt.Errorf("checking the driver's other rides: %w", err)
	}
	return busy, nil
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
// version (a prefix of the selfie's hash), then how the ride was paid —
// settled by hand (paid_mode) or by the order in `po`, with that order's
// whole amount — the shape scanUserBooking reads. Select it FROM
// userBookingTables.
const userBookingColumns = bookingColumnsB + `,
	d.name, d.phone_e164,
	(SELECT avg(x.driver_rating)::float8 FROM bookings x WHERE x.driver_id = b.driver_id),
	(SELECT count(x.driver_rating) FROM bookings x WHERE x.driver_id = b.driver_id),
	(SELECT left(dd.sha256, 12) FROM driver_documents dd
	 WHERE dd.driver_id = b.driver_id AND dd.kind = 'selfie'),
	coalesce(b.paid_mode, ''), coalesce(po.merchant_order_id, ''),
	coalesce(po.payment_mode, ''), coalesce(po.utr, ''), coalesce(po.transaction_id, ''),
	coalesce(po.amount_paise, 0)`

// userBookingTables is what userBookingColumns reads from.
const userBookingTables = `bookings b
	LEFT JOIN drivers d ON d.id = b.driver_id
	LEFT JOIN payment_orders po ON po.merchant_order_id = b.payment_order_id`

// ListForUser returns userID's bookings with their assigned drivers, latest
// scheduled first.
func (r *BookingRepository) ListForUser(ctx context.Context, userID string, limit int) ([]domain.UserBooking, error) {
	q := `
		SELECT ` + userBookingColumns + `
		FROM ` + userBookingTables + `
		WHERE b.user_id = $1
		ORDER BY b.scheduled_at DESC NULLS LAST, b.created_at DESC
		LIMIT $2`

	rows, err := r.db.Query(ctx, q, userID, limit)
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
		FROM ` + userBookingTables + `
		WHERE b.id = $1 AND b.user_id = $2`
	ub, err := scanUserBooking(r.db.QueryRow(ctx, q, id, userID))
	if err != nil {
		return domain.UserBooking{}, bookingErr(rideErr(err, ErrBookingNotFound, "finding booking"))
	}
	return ub, nil
}

// PaymentLines returns, for each of userID's payment orders named in
// merchantOrderIDs, the bookings it paid — only userID's own — oldest
// scheduled first, each with its part of the order and whether it was a
// ride's fare or a cancellation fee. Orders that aren't userID's, or that
// don't exist, are left out. It reads, never writes.
func (r *BookingRepository) PaymentLines(
	ctx context.Context, userID string, merchantOrderIDs []string,
) (map[string][]domain.PaymentLine, error) {
	if len(merchantOrderIDs) == 0 {
		return nil, nil
	}
	rows, err := r.db.Query(ctx, `
		SELECT i.merchant_order_id, b.id::text, b.trip_type, b.scheduled_at, i.amount_paise,
		       b.status = 'cancelled' AND b.cancellation_fee_paise IS NOT NULL
		FROM payment_order_items i
		JOIN payment_orders po ON po.merchant_order_id = i.merchant_order_id
		JOIN bookings b ON b.id = i.booking_id
		WHERE i.merchant_order_id = ANY($2::text[]) AND po.user_id = $1 AND b.user_id = $1
		ORDER BY i.merchant_order_id, b.scheduled_at NULLS LAST, b.created_at, b.id`,
		userID, merchantOrderIDs)
	if err != nil {
		return nil, fmt.Errorf("listing payment lines: %w", err)
	}
	defer rows.Close()
	out := map[string][]domain.PaymentLine{}
	for rows.Next() {
		var (
			order string
			line  domain.PaymentLine
			fee   bool
		)
		if err := rows.Scan(&order, &line.BookingID, &line.TripType, &line.ScheduledAt,
			&line.AmountPaise, &fee); err != nil {
			return nil, fmt.Errorf("listing payment lines: %w", err)
		}
		line.Kind = domain.PaymentLineRide
		if fee {
			line.Kind = domain.PaymentLineCancellationFee
		}
		out[order] = append(out[order], line)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("listing payment lines: %w", err)
	}
	return out, nil
}

// PickupCancel is whether Cancel may cancel a booking whose driver is
// already waiting at the pickup, and the fee that charges (0 for none).
type PickupCancel struct {
	Allowed  bool
	FeePaise int64
}

// Cancel cancels userID's booking id for the customer, provided the trip
// hasn't started: it must still be requested or accepted, or arrived when
// atPickup allows it — charging atPickup.FeePaise then. The driver stays on
// the row so their rides list shows it as cancelled; the start code is
// cleared. Returns the cancelled booking, [ErrBookingNotFound], or
// [ErrBookingStateConflict] (including an arrived booking atPickup doesn't
// allow).
func (r *BookingRepository) Cancel(
	ctx context.Context, id, userID, reason string, at time.Time, atPickup PickupCancel,
) (domain.Booking, error) {
	// SET reads the row as it was, so the fee goes only on a booking that
	// was at the pickup.
	q := `
		UPDATE bookings
		SET status = 'cancelled', cancelled_at = $3, cancelled_by = $4,
		    cancel_reason = nullif($5, ''), start_otp = NULL,
		    cancellation_fee_paise = CASE WHEN status = 'arrived' THEN nullif($7::bigint, 0) END
		WHERE id = $1 AND user_id = $2
		  AND (status IN ('requested', 'accepted') OR (status = 'arrived' AND $6))
		RETURNING ` + bookingColumns
	b, err := scanBooking(r.db.QueryRow(ctx, q, id, userID, at, domain.CancelledByCustomer, reason,
		atPickup.Allowed, atPickup.FeePaise))
	if err != nil {
		return domain.Booking{}, r.whyUnchanged(ctx, err, id, userID, "cancelling booking")
	}
	return b, nil
}

// EndEarly completes userID's trip id at at, before its booked end, on the
// customer's say: the fare becomes farePaise (the charge for the time used)
// and the booked fare is kept in booked_fare_paise. Only a trip in
// progress; [ErrBookingNotFound] or [ErrBookingStateConflict] otherwise.
func (r *BookingRepository) EndEarly(ctx context.Context, id, userID string, farePaise int64, at time.Time) (domain.Booking, error) {
	q := `
		UPDATE bookings
		SET status = 'completed', completed_at = $3,
		    booked_fare_paise = fare_paise, fare_paise = $4
		WHERE id = $1 AND user_id = $2 AND status = 'in_progress'
		RETURNING ` + bookingColumns
	b, err := scanBooking(r.db.QueryRow(ctx, q, id, userID, at, farePaise))
	if err != nil {
		return domain.Booking{}, r.whyUnchanged(ctx, err, id, userID, "ending trip")
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
	if err := r.db.QueryRow(ctx, q, id, userID, rating.Stars, rating.Note).Scan(&got); err != nil {
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
	if err := r.db.QueryRow(ctx,
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
		pay         domain.BookingPayment
		paidMode    string
	)
	br := bookingRow{b: &ub.Booking}
	err := row.Scan(br.targets(&name, &phone, &average, &rated, &photo,
		&paidMode, &pay.MerchantOrderID, &pay.Mode, &pay.UTR, &pay.TransactionID, &pay.TotalPaise)...)
	br.finish()
	if at := ub.Booking.PaidAt; at != nil {
		pay.PaidAt = *at
		if paidMode != "" {
			// Settled by hand: no gateway order, nothing to quote.
			pay = domain.BookingPayment{Mode: strings.ToUpper(paidMode), PaidAt: *at}
		}
		ub.Payment = &pay
	}
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
