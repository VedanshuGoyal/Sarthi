package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// SettleByHand closes the bill of booking id without the gateway — a
// completed ride, or a cancellation that charged a fee — with the
// operator's note:
//
//   - cash: the customer paid the driver directly. paid_paise and
//     commission_paise are zero: MOJUD received nothing and owes the driver
//     nothing.
//   - waived: the customer pays nothing, and MOJUD pays the driver their
//     usual share itself. paid_paise is what was owed (the amount MOJUD
//     covers) and commission_paise its usual cut at commissionBP basis
//     points, rounded as PaymentService.commission rounds, so the payout
//     owes the driver the same as if the customer had paid.
//
// Either way the booking is stamped paid, which is what lets its customer
// book again.
//
// A booking with a gateway order still pending or completed is refused with
// [ErrGatewayOrderOpen]: the customer may have paid (or be paying) by UPI,
// and stamping it by hand would leave that money owed to nobody. Sync the
// booking's orders with the gateway first so only a live one blocks.
//
// Returns the booking, [ErrBookingNotFound], or [ErrBookingStateConflict]
// when there is nothing to pay or it is already paid.
func (r *PaymentRepository) SettleByHand(
	ctx context.Context, id string, mode domain.SettleMode, note string, commissionBP int64, at time.Time,
) (domain.Booking, error) {
	b, err := scanBooking(r.db.QueryRow(ctx, `
		UPDATE bookings
		SET paid_at = $2, paid_mode = $3, paid_note = nullif($4, ''),
		    paid_paise       = CASE WHEN $3 = 'waived' THEN `+owedPaise+` ELSE 0 END,
		    commission_paise = CASE WHEN $3 = 'waived' THEN (`+owedPaise+` * $5 + 5000) / 10000 ELSE 0 END
		WHERE id = $1 AND paid_at IS NULL
		  AND (status = 'completed' OR (status = 'cancelled' AND cancellation_fee_paise IS NOT NULL))
		  AND NOT EXISTS (SELECT 1 FROM payment_orders po
		                  WHERE po.state IN ('pending', 'completed')
		                    AND (po.booking_id = bookings.id
		                         OR po.merchant_order_id IN (SELECT merchant_order_id FROM payment_order_items
		                                                     WHERE booking_id = bookings.id)))
		RETURNING `+bookingColumns,
		id, at, string(mode), note, commissionBP))
	if err != nil {
		err = bookingExplain(ctx, r.db, err, id, "settling booking")
		if errors.Is(err, ErrBookingStateConflict) {
			var open bool
			if qerr := r.db.QueryRow(ctx, `
				SELECT EXISTS (SELECT 1 FROM payment_orders po JOIN bookings b
				                 ON b.id = po.booking_id
				                 OR b.id IN (SELECT booking_id FROM payment_order_items i
				                             WHERE i.merchant_order_id = po.merchant_order_id)
				               WHERE b.id = $1 AND b.paid_at IS NULL
				                 AND (b.status = 'completed' OR b.cancellation_fee_paise IS NOT NULL)
				                 AND po.state IN ('pending', 'completed'))`, id).Scan(&open); qerr == nil && open {
				return domain.Booking{}, ErrGatewayOrderOpen
			}
		}
		return domain.Booking{}, err
	}
	return b, nil
}

// owedPaise is what a booking's customer owes: a completed ride's fare, or a
// cancellation's fee.
const owedPaise = `(CASE WHEN status = 'completed' THEN fare_paise ELSE cancellation_fee_paise END)`

// ErrGatewayOrderOpen refuses settling a ride by hand while one of its UPI
// checkouts is pending or completed. It matches [ErrBookingStateConflict].
var ErrGatewayOrderOpen = fmt.Errorf("%w: the customer has a UPI payment open or paid for this ride; "+
	"wait for it to finish, or check Payments", ErrBookingStateConflict)

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
	// An order paying several bookings is listed once, for the first of
	// them something else had paid.
	out.PaidTwice, err = r.attentionOrders(ctx, `
		SELECT * FROM (
		    SELECT DISTINCT ON (po.merchant_order_id) `+attentionColumns+`
		    FROM payment_orders po JOIN bookings b
		      ON b.id = po.booking_id
		      OR b.id IN (SELECT booking_id FROM payment_order_items i
		                  WHERE i.merchant_order_id = po.merchant_order_id)
		    WHERE po.state = 'completed' AND po.merchant_order_id IS DISTINCT FROM b.payment_order_id
		    ORDER BY po.merchant_order_id, b.id
		) twice
		ORDER BY updated_at DESC
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
