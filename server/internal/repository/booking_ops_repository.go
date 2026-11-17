package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// AdminBookingFilter narrows the back office's bookings list. Zero fields
// don't filter.
type AdminBookingFilter struct {
	// Status is a stored status ("requested", "completed", …).
	Status domain.RideStatus
	// Unpaid keeps only completed rides the customer hasn't paid for.
	Unpaid bool
	// ScheduledFrom / ScheduledBefore bound the start time, [from, before).
	ScheduledFrom, ScheduledBefore time.Time
	Limit                          int
}

// adminBookingColumns is bookingColumnsB plus the customer from `u`, the
// driver from `d` (NULLs until one accepts) and how the ride was settled.
const adminBookingColumns = bookingColumnsB + `,
	u.id::text, u.name, u.phone_e164,
	d.id::text, d.name, d.phone_e164,
	coalesce(b.paid_mode, ''), coalesce(b.paid_note, '')`

// ListForAdmin returns the bookings f picks, latest scheduled first, with
// their customer, driver and settlement. Ops only: it carries phone numbers.
func (r *BookingRepository) ListForAdmin(ctx context.Context, f AdminBookingFilter) ([]domain.AdminBookingRow, error) {
	var from, before *time.Time
	if !f.ScheduledFrom.IsZero() {
		from = &f.ScheduledFrom
	}
	if !f.ScheduledBefore.IsZero() {
		before = &f.ScheduledBefore
	}
	rows, err := r.db.Query(ctx, `
		SELECT `+adminBookingColumns+`
		FROM bookings b
		JOIN users u ON u.id = b.user_id
		LEFT JOIN drivers d ON d.id = b.driver_id
		WHERE ($1 = '' OR b.status = $1)
		  AND (NOT $2 OR (b.status = 'completed' AND b.paid_at IS NULL))
		  AND ($3::timestamptz IS NULL OR b.scheduled_at >= $3)
		  AND ($4::timestamptz IS NULL OR b.scheduled_at < $4)
		ORDER BY b.scheduled_at DESC NULLS LAST, b.created_at DESC
		LIMIT $5`,
		string(f.Status), f.Unpaid, from, before, f.Limit)
	if err != nil {
		return nil, fmt.Errorf("listing bookings for admin: %w", err)
	}
	defer rows.Close()
	out := []domain.AdminBookingRow{}
	for rows.Next() {
		row, err := scanAdminBooking(rows)
		if err != nil {
			return nil, fmt.Errorf("listing bookings for admin: %w", err)
		}
		out = append(out, row)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("listing bookings for admin: %w", err)
	}
	return out, nil
}

// FindForAdmin returns one booking as ListForAdmin reads it, or
// [ErrBookingNotFound].
func (r *BookingRepository) FindForAdmin(ctx context.Context, id string) (domain.AdminBookingRow, error) {
	row, err := scanAdminBooking(r.db.QueryRow(ctx, `
		SELECT `+adminBookingColumns+`
		FROM bookings b
		JOIN users u ON u.id = b.user_id
		LEFT JOIN drivers d ON d.id = b.driver_id
		WHERE b.id = $1`, id))
	if err != nil {
		return domain.AdminBookingRow{}, bookingErr(rideErr(err, ErrBookingNotFound, "finding booking"))
	}
	return row, nil
}

func scanAdminBooking(row pgx.Row) (domain.AdminBookingRow, error) {
	var (
		out                            domain.AdminBookingRow
		driverID, driverName, driverPh *string
	)
	br := bookingRow{b: &out.Booking}
	c := &out.Customer
	err := row.Scan(br.targets(&c.ID, &c.Name, &c.Phone, &driverID, &driverName, &driverPh,
		&out.PaidMode, &out.PaidNote)...)
	br.finish()
	if driverID != nil {
		d := domain.AdminParty{ID: *driverID}
		if driverName != nil {
			d.Name = *driverName
		}
		if driverPh != nil {
			d.Phone = *driverPh
		}
		out.Driver = &d
	}
	return out, err
}

// CancelByOps cancels booking id for MOJUD, at any step before it's
// completed — including a trip underway that is stuck or shouldn't be
// happening. The driver stays on the row so their rides list shows it as
// cancelled; the start code is cleared. Returns the cancelled booking,
// [ErrBookingNotFound], or [ErrBookingStateConflict] once it's completed or
// already cancelled.
func (r *BookingRepository) CancelByOps(ctx context.Context, id, reason string, at time.Time) (domain.Booking, error) {
	b, err := scanBooking(r.db.QueryRow(ctx, `
		UPDATE bookings
		SET status = 'cancelled', cancelled_at = $2, cancelled_by = $3,
		    cancel_reason = nullif($4, ''), start_otp = NULL
		WHERE id = $1 AND status IN ('requested', 'accepted', 'arrived', 'in_progress')
		RETURNING `+bookingColumns,
		id, at, domain.CancelledByOps, reason))
	if err != nil {
		return domain.Booking{}, bookingExplain(ctx, r.db, err, id, "cancelling booking")
	}
	return b, nil
}

// bookingExplain explains an ops UPDATE on booking id that matched no row:
// there's no such booking ([ErrBookingNotFound]) or it isn't at a step the
// change follows from ([ErrBookingStateConflict]). Other errors are wrapped
// with doing.
func bookingExplain(ctx context.Context, db DB, err error, id, doing string) error {
	if !errors.Is(err, pgx.ErrNoRows) {
		return bookingErr(rideErr(err, ErrBookingNotFound, doing))
	}
	var exists bool
	if err := db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM bookings WHERE id = $1)`, id).Scan(&exists); err != nil {
		return fmt.Errorf("%s: %w", doing, err)
	}
	if !exists {
		return ErrBookingNotFound
	}
	return ErrBookingStateConflict
}
