package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// SettleByHand closes the bill of completed booking id without the gateway:
// mode cash (the customer paid the driver) or waived (nobody pays), with
// the operator's note. The ride is stamped paid like a gateway payment —
// which is what lets its customer book again — but with paid_paise and
// commission_paise zero: MOJUD received nothing, so a payout owes its
// driver nothing for it.
//
// Returns the booking, [ErrBookingNotFound], or [ErrBookingStateConflict]
// when it isn't completed or is already paid.
func (r *PaymentRepository) SettleByHand(
	ctx context.Context, id string, mode domain.SettleMode, note string, at time.Time,
) (domain.Booking, error) {
	b, err := scanBooking(r.db.QueryRow(ctx, `
		UPDATE bookings
		SET paid_at = $2, paid_paise = 0, commission_paise = 0,
		    paid_mode = $3, paid_note = nullif($4, '')
		WHERE id = $1 AND status = 'completed' AND paid_at IS NULL
		RETURNING `+bookingColumns,
		id, at, string(mode), note))
	if err != nil {
		return domain.Booking{}, bookingExplain(ctx, r.db, err, id, "settling booking")
	}
	return b, nil
}

// attentionColumns is one payment order plus what its booking was actually
// paid by, from `po` and `b`.
const attentionColumns = `po.merchant_order_id, po.booking_id::text, po.user_id::text, po.amount_paise,
	po.state, coalesce(po.transaction_id, ''), coalesce(po.payment_mode, ''), coalesce(po.utr, ''),
	po.created_at, po.updated_at, coalesce(b.payment_order_id, b.paid_mode, '')`

// PaymentAttention lists the orders someone has to look at, up to limit of
// each kind: completed orders whose ride was paid by something else — a
// second payment, owed back to the customer — and orders still pending that
// were opened before pendingBefore, which the sweep no longer re-checks.
func (r *PaymentRepository) PaymentAttention(ctx context.Context, pendingBefore time.Time, limit int) (domain.PaymentAttention, error) {
	var (
		out domain.PaymentAttention
		err error
	)
	out.PaidTwice, err = r.attentionOrders(ctx, `
		SELECT `+attentionColumns+`
		FROM payment_orders po JOIN bookings b ON b.id = po.booking_id
		WHERE po.state = 'completed' AND po.merchant_order_id IS DISTINCT FROM b.payment_order_id
		ORDER BY po.updated_at DESC
		LIMIT $1`, limit)
	if err != nil {
		return domain.PaymentAttention{}, err
	}
	out.StalePending, err = r.attentionOrders(ctx, `
		SELECT `+attentionColumns+`
		FROM payment_orders po JOIN bookings b ON b.id = po.booking_id
		WHERE po.state = 'pending' AND po.created_at < $2
		ORDER BY po.created_at
		LIMIT $1`, limit, pendingBefore)
	if err != nil {
		return domain.PaymentAttention{}, err
	}
	return out, nil
}

func (r *PaymentRepository) attentionOrders(ctx context.Context, q string, args ...any) ([]domain.AttentionOrder, error) {
	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("listing payment orders needing attention: %w", err)
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (domain.AttentionOrder, error) {
		var o domain.AttentionOrder
		err := row.Scan(&o.MerchantOrderID, &o.BookingID, &o.UserID, &o.AmountPaise,
			&o.State, &o.TransactionID, &o.PaymentMode, &o.UTR,
			&o.CreatedAt, &o.UpdatedAt, &o.PaidBy)
		return o, err
	})
}

// PayoutsForDriver lists the transfers recorded to driverID, newest first,
// at most limit.
func (r *PaymentRepository) PayoutsForDriver(ctx context.Context, driverID string, limit int) ([]domain.DriverPayout, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id::text, driver_id::text, amount_paise, rides, reference, created_at
		FROM driver_payouts
		WHERE driver_id = $1
		ORDER BY created_at DESC
		LIMIT $2`, driverID, limit)
	if err != nil {
		return nil, fmt.Errorf("listing a driver's payouts: %w", err)
	}
	out, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (domain.DriverPayout, error) {
		var p domain.DriverPayout
		err := row.Scan(&p.ID, &p.DriverID, &p.AmountPaise, &p.Rides, &p.Reference, &p.CreatedAt)
		return p, err
	})
	if err != nil {
		return nil, fmt.Errorf("listing a driver's payouts: %w", err)
	}
	return out, nil
}
