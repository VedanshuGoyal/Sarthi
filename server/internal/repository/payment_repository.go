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

// ErrPaymentOrderNotFound is returned when no payment order has the id.
var ErrPaymentOrderNotFound = errors.New("payment order not found")

// ErrNothingToPayOut is returned when a driver has no paid rides waiting
// for a payout.
var ErrNothingToPayOut = errors.New("this driver has no paid rides waiting for a payout")

// PaymentRepository persists checkouts (payment_orders), the paid state of
// bookings, and payouts to drivers.
type PaymentRepository struct {
	pool *pgxpool.Pool
}

// NewPaymentRepository wires the repository to a connection pool.
func NewPaymentRepository(pool *pgxpool.Pool) *PaymentRepository {
	return &PaymentRepository{pool: pool}
}

const paymentOrderColumns = `merchant_order_id, booking_id, user_id, amount_paise,
	provider_order_id, state, coalesce(transaction_id, ''), coalesce(payment_mode, ''),
	coalesce(utr, ''), expires_at, created_at`

func scanPaymentOrder(row pgx.Row) (domain.PaymentOrder, error) {
	var o domain.PaymentOrder
	err := row.Scan(&o.MerchantOrderID, &o.BookingID, &o.UserID, &o.AmountPaise,
		&o.ProviderOrderID, &o.State, &o.TransactionID, &o.PaymentMode,
		&o.UTR, &o.ExpiresAt, &o.CreatedAt)
	return o, err
}

// InsertOrder records a checkout the gateway just opened, as pending.
func (r *PaymentRepository) InsertOrder(ctx context.Context, o domain.PaymentOrder) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO payment_orders
		    (merchant_order_id, booking_id, user_id, amount_paise, provider_order_id, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		o.MerchantOrderID, o.BookingID, o.UserID, o.AmountPaise, o.ProviderOrderID, o.ExpiresAt)
	if err != nil {
		return fmt.Errorf("inserting payment order: %w", err)
	}
	return nil
}

// FindOrder returns the order merchantOrderID, or [ErrPaymentOrderNotFound].
func (r *PaymentRepository) FindOrder(ctx context.Context, merchantOrderID string) (domain.PaymentOrder, error) {
	o, err := scanPaymentOrder(r.pool.QueryRow(ctx,
		`SELECT `+paymentOrderColumns+` FROM payment_orders WHERE merchant_order_id = $1`,
		merchantOrderID))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.PaymentOrder{}, ErrPaymentOrderNotFound
	}
	if err != nil {
		return domain.PaymentOrder{}, fmt.Errorf("finding payment order: %w", err)
	}
	return o, nil
}

// PendingForBooking returns bookingID's orders still pending, newest first.
func (r *PaymentRepository) PendingForBooking(ctx context.Context, bookingID string) ([]domain.PaymentOrder, error) {
	return r.queryOrders(ctx, `
		SELECT `+paymentOrderColumns+` FROM payment_orders
		WHERE booking_id = $1 AND state = 'pending'
		ORDER BY created_at DESC`, bookingID)
}

// PendingSince returns every order still pending that was opened between
// from and to, oldest first — the sweep's work list.
func (r *PaymentRepository) PendingSince(ctx context.Context, from, to time.Time) ([]domain.PaymentOrder, error) {
	return r.queryOrders(ctx, `
		SELECT `+paymentOrderColumns+` FROM payment_orders
		WHERE state = 'pending' AND created_at >= $1 AND created_at < $2
		ORDER BY created_at`, from, to)
}

func (r *PaymentRepository) queryOrders(ctx context.Context, q string, args ...any) ([]domain.PaymentOrder, error) {
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("listing payment orders: %w", err)
	}
	defer rows.Close()
	var out []domain.PaymentOrder
	for rows.Next() {
		o, err := scanPaymentOrder(rows)
		if err != nil {
			return nil, fmt.Errorf("listing payment orders: %w", err)
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// FailOrder marks a pending order failed.
func (r *PaymentRepository) FailOrder(ctx context.Context, merchantOrderID string, st domain.GatewayOrderStatus, at time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE payment_orders
		SET state = 'failed', transaction_id = nullif($2, ''), payment_mode = nullif($3, ''), updated_at = $4
		WHERE merchant_order_id = $1 AND state = 'pending'`,
		merchantOrderID, st.TransactionID, st.PaymentMode, at)
	if err != nil {
		return fmt.Errorf("failing payment order: %w", err)
	}
	return nil
}

// CompleteOrder marks a pending order completed and, if its booking isn't
// paid yet, marks the booking paid by it with commissionPaise as MOJUD's
// cut — in one transaction. The outcome says whether this call paid the
// booking, found the order already recorded, or found the booking paid by
// another order. The booking is returned either way.
func (r *PaymentRepository) CompleteOrder(ctx context.Context, o domain.PaymentOrder, st domain.GatewayOrderStatus, commissionPaise int64, at time.Time) (domain.SettleOutcome, domain.Booking, error) {
	outcome := domain.SettledAlready
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return outcome, domain.Booking{}, fmt.Errorf("completing payment order: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx, `
		UPDATE payment_orders
		SET state = 'completed', transaction_id = nullif($2, ''), payment_mode = nullif($3, ''),
		    utr = nullif($4, ''), updated_at = $5
		WHERE merchant_order_id = $1 AND state = 'pending'`,
		o.MerchantOrderID, st.TransactionID, st.PaymentMode, st.UTR, at)
	if err != nil {
		return outcome, domain.Booking{}, fmt.Errorf("completing payment order: %w", err)
	}
	if tag.RowsAffected() == 1 {
		tag, err = tx.Exec(ctx, `
			UPDATE bookings
			SET paid_at = $2, paid_paise = $3, commission_paise = $4, payment_order_id = $5
			WHERE id = $1 AND paid_at IS NULL`,
			o.BookingID, at, st.AmountPaise, commissionPaise, o.MerchantOrderID)
		if err != nil {
			return outcome, domain.Booking{}, fmt.Errorf("marking booking paid: %w", err)
		}
		outcome = domain.SettledPaidTwice
		if tag.RowsAffected() == 1 {
			outcome = domain.SettledNow
		}
	}
	b, err := scanBooking(tx.QueryRow(ctx, `SELECT `+bookingColumns+` FROM bookings WHERE id = $1`, o.BookingID))
	if err != nil {
		return outcome, domain.Booking{}, fmt.Errorf("reading paid booking: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return outcome, domain.Booking{}, fmt.Errorf("completing payment order: %w", err)
	}
	return outcome, b, nil
}

// DuePayouts lists, per driver, the share of every ride paid on or before
// asOf that hasn't been paid out, with their bank details (number still
// sealed). Largest first.
func (r *PaymentRepository) DuePayouts(ctx context.Context, asOf time.Time) ([]domain.PayoutDue, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT d.id, d.name, d.phone_e164,
		       count(*), sum(b.paid_paise - coalesce(b.commission_paise, 0)),
		       coalesce(a.account_holder_name, ''), a.account_number_encrypted,
		       coalesce(a.ifsc_code, '')
		FROM bookings b
		JOIN drivers d ON d.id = b.driver_id
		LEFT JOIN driver_bank_accounts a ON a.driver_id = d.id
		WHERE b.paid_at IS NOT NULL AND b.payout_id IS NULL AND b.paid_at <= $1
		GROUP BY d.id, d.name, d.phone_e164, a.account_holder_name, a.account_number_encrypted, a.ifsc_code
		ORDER BY 5 DESC`, asOf)
	if err != nil {
		return nil, fmt.Errorf("listing due payouts: %w", err)
	}
	defer rows.Close()
	out := []domain.PayoutDue{}
	for rows.Next() {
		var p domain.PayoutDue
		if err := rows.Scan(&p.DriverID, &p.DriverName, &p.DriverPhone, &p.Rides, &p.AmountPaise,
			&p.AccountHolderName, &p.AccountNumberEncrypted, &p.IFSCCode); err != nil {
			return nil, fmt.Errorf("listing due payouts: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// RecordPayout records one transfer to driverID covering every ride of
// theirs paid on or before asOf and not yet paid out, and stamps those
// rides with it — in one transaction. [ErrNothingToPayOut] when there are
// none.
func (r *PaymentRepository) RecordPayout(ctx context.Context, driverID, reference string, asOf, at time.Time) (domain.DriverPayout, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Lock the rides so a concurrent payout can't claim them too.
	var (
		rides  int
		amount int64
	)
	err = tx.QueryRow(ctx, `
		WITH due AS (
		    SELECT paid_paise - coalesce(commission_paise, 0) AS share
		    FROM bookings
		    WHERE driver_id = $1 AND paid_at IS NOT NULL AND payout_id IS NULL AND paid_at <= $2
		    FOR UPDATE
		)
		SELECT count(*), coalesce(sum(share), 0) FROM due`, driverID, asOf).Scan(&rides, &amount)
	if err != nil {
		return domain.DriverPayout{}, rideErr(err, ErrNothingToPayOut, "recording payout")
	}
	if rides == 0 || amount <= 0 {
		return domain.DriverPayout{}, ErrNothingToPayOut
	}

	p := domain.DriverPayout{DriverID: driverID, AmountPaise: amount, Rides: rides, Reference: reference}
	if err := tx.QueryRow(ctx, `
		INSERT INTO driver_payouts (driver_id, amount_paise, rides, reference, created_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at`,
		driverID, amount, rides, reference, at).Scan(&p.ID, &p.CreatedAt); err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE bookings SET payout_id = $3
		WHERE driver_id = $1 AND paid_at IS NOT NULL AND payout_id IS NULL AND paid_at <= $2`,
		driverID, asOf, p.ID); err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	return p, nil
}
