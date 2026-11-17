package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// ErrPaymentOrderNotFound is returned when no payment order has the id.
var ErrPaymentOrderNotFound = errors.New("payment order not found")

// ErrNothingToPayOut is returned when a driver has no paid rides waiting
// for a payout.
var ErrNothingToPayOut = errors.New("this driver has no paid rides waiting for a payout")

// ErrPayoutMismatch is returned when the rides a payout would cover don't add
// up to what the caller expected — the list it was read from is out of date.
var ErrPayoutMismatch = errors.New("what this driver is owed has changed since the list was read; reload it and check the transfer")

// ExpectedPayout is what the caller saw owed on the payouts list. A nil
// field isn't checked.
type ExpectedPayout struct {
	AmountPaise *int64
	Rides       *int
}

// PaymentRepository persists checkouts (payment_orders), the paid state of
// bookings, and payouts to drivers.
type PaymentRepository struct {
	db DB
}

// NewPaymentRepository wires the repository to a pool (or a transaction).
func NewPaymentRepository(db DB) *PaymentRepository {
	return &PaymentRepository{db: db}
}

const paymentOrderColumns = `merchant_order_id, booking_id, user_id, amount_paise,
	provider_order_id, coalesce(checkout_token, ''), state, coalesce(transaction_id, ''),
	coalesce(payment_mode, ''), coalesce(utr, ''), expires_at, created_at`

func scanPaymentOrder(row pgx.Row) (domain.PaymentOrder, error) {
	var o domain.PaymentOrder
	err := row.Scan(&o.MerchantOrderID, &o.BookingID, &o.UserID, &o.AmountPaise,
		&o.ProviderOrderID, &o.CheckoutToken, &o.State, &o.TransactionID, &o.PaymentMode,
		&o.UTR, &o.ExpiresAt, &o.CreatedAt)
	return o, err
}

// InsertOrder records a checkout the gateway just opened, as pending, with
// the bookings it pays (o.Items; just its own booking for the whole amount
// when empty) — in one transaction.
func (r *PaymentRepository) InsertOrder(ctx context.Context, o domain.PaymentOrder) error {
	items := o.Items
	if len(items) == 0 {
		items = []domain.PaymentItem{{BookingID: o.BookingID, AmountPaise: o.AmountPaise}}
	}
	var sum int64
	for _, it := range items {
		sum += it.AmountPaise
	}
	if sum != o.AmountPaise {
		return fmt.Errorf("inserting payment order: items add up to %d, not %d", sum, o.AmountPaise)
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("inserting payment order: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `
		INSERT INTO payment_orders
		    (merchant_order_id, booking_id, user_id, amount_paise, provider_order_id, checkout_token, expires_at)
		VALUES ($1, $2, $3, $4, $5, nullif($6, ''), $7)`,
		o.MerchantOrderID, o.BookingID, o.UserID, o.AmountPaise, o.ProviderOrderID, o.CheckoutToken, o.ExpiresAt); err != nil {
		return fmt.Errorf("inserting payment order: %w", err)
	}
	for _, it := range items {
		if _, err := tx.Exec(ctx, `
			INSERT INTO payment_order_items (merchant_order_id, booking_id, amount_paise) VALUES ($1, $2, $3)`,
			o.MerchantOrderID, it.BookingID, it.AmountPaise); err != nil {
			return fmt.Errorf("inserting payment order item: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("inserting payment order: %w", err)
	}
	return nil
}

// OrderItems returns the bookings order merchantOrderID pays, ordered by
// booking id.
func (r *PaymentRepository) OrderItems(ctx context.Context, merchantOrderID string) ([]domain.PaymentItem, error) {
	return orderItems(ctx, r.db, merchantOrderID)
}

func orderItems(ctx context.Context, db DB, merchantOrderID string) ([]domain.PaymentItem, error) {
	rows, err := db.Query(ctx, `
		SELECT booking_id::text, amount_paise FROM payment_order_items
		WHERE merchant_order_id = $1 ORDER BY booking_id`, merchantOrderID)
	if err != nil {
		return nil, fmt.Errorf("listing payment order items: %w", err)
	}
	defer rows.Close()
	var out []domain.PaymentItem
	for rows.Next() {
		var it domain.PaymentItem
		if err := rows.Scan(&it.BookingID, &it.AmountPaise); err != nil {
			return nil, fmt.Errorf("listing payment order items: %w", err)
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// FindOrder returns the order merchantOrderID, or [ErrPaymentOrderNotFound].
func (r *PaymentRepository) FindOrder(ctx context.Context, merchantOrderID string) (domain.PaymentOrder, error) {
	o, err := scanPaymentOrder(r.db.QueryRow(ctx,
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

// PendingForBooking returns the orders still pending that pay bookingID —
// opened on it, or carrying it — newest first.
func (r *PaymentRepository) PendingForBooking(ctx context.Context, bookingID string) ([]domain.PaymentOrder, error) {
	return r.PendingForBookings(ctx, []string{bookingID})
}

// PendingForBookings returns the orders still pending that pay any of
// bookingIDs, each once, newest first.
func (r *PaymentRepository) PendingForBookings(ctx context.Context, bookingIDs []string) ([]domain.PaymentOrder, error) {
	return r.queryOrders(ctx, `
		SELECT `+paymentOrderColumns+` FROM payment_orders
		WHERE state = 'pending'
		  AND (booking_id = ANY($1::uuid[])
		       OR merchant_order_id IN (SELECT merchant_order_id FROM payment_order_items
		                                WHERE booking_id = ANY($1::uuid[])))
		ORDER BY created_at DESC`, bookingIDs)
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
	rows, err := r.db.Query(ctx, q, args...)
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
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders
		SET state = 'failed', transaction_id = nullif($2, ''), payment_mode = nullif($3, ''), updated_at = $4
		WHERE merchant_order_id = $1 AND state = 'pending'`,
		merchantOrderID, st.TransactionID, st.PaymentMode, at)
	if err != nil {
		return fmt.Errorf("failing payment order: %w", err)
	}
	return nil
}

// CompleteOrder marks a pending order completed and each booking it pays
// that isn't paid yet as paid by it — its own part of the amount, and
// MOJUD's cut of that part at commissionBP basis points (rounded as
// PaymentService.commission rounds) — in one transaction. An order without
// items (opened by an older server) pays its own booking in full. The
// result says whether this call paid them, found the order already
// recorded, or found some paid by something else first.
func (r *PaymentRepository) CompleteOrder(
	ctx context.Context, o domain.PaymentOrder, st domain.GatewayOrderStatus, commissionBP int64, at time.Time,
) (domain.SettleResult, error) {
	res := domain.SettleResult{Outcome: domain.SettledAlready}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return res, fmt.Errorf("completing payment order: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx, `
		UPDATE payment_orders
		SET state = 'completed', transaction_id = nullif($2, ''), payment_mode = nullif($3, ''),
		    utr = nullif($4, ''), updated_at = $5
		WHERE merchant_order_id = $1 AND state = 'pending'`,
		o.MerchantOrderID, st.TransactionID, st.PaymentMode, st.UTR, at)
	if err != nil {
		return res, fmt.Errorf("completing payment order: %w", err)
	}
	if tag.RowsAffected() == 1 {
		items, err := orderItems(ctx, tx, o.MerchantOrderID)
		if err != nil {
			return res, err
		}
		if len(items) == 0 {
			items = []domain.PaymentItem{{BookingID: o.BookingID, AmountPaise: o.AmountPaise}}
		}
		for _, it := range items {
			b, err := scanBooking(tx.QueryRow(ctx, `
				UPDATE bookings
				SET paid_at = $2, paid_paise = $3, commission_paise = $4, payment_order_id = $5
				WHERE id = $1 AND paid_at IS NULL
				RETURNING `+bookingColumns,
				it.BookingID, at, it.AmountPaise, (it.AmountPaise*commissionBP+5000)/10000, o.MerchantOrderID))
			switch {
			case errors.Is(err, pgx.ErrNoRows):
				res.AlreadyPaid = append(res.AlreadyPaid, it.BookingID)
			case err != nil:
				return res, fmt.Errorf("marking booking paid: %w", err)
			default:
				res.Paid = append(res.Paid, b)
			}
		}
		res.Outcome = domain.SettledNow
		if len(res.AlreadyPaid) > 0 {
			res.Outcome = domain.SettledPaidTwice
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.SettleResult{Outcome: domain.SettledAlready}, fmt.Errorf("completing payment order: %w", err)
	}
	return res, nil
}

// DuePayouts lists, per driver, the share of every ride paid on or before
// asOf that hasn't been paid out, with their bank details (number still
// sealed), KYC status and when the bank confirmed the account. Largest
// first.
func (r *PaymentRepository) DuePayouts(ctx context.Context, asOf time.Time) ([]domain.PayoutDue, error) {
	rows, err := r.db.Query(ctx, `
		SELECT d.id, d.name, d.phone_e164,
		       count(*), sum(b.paid_paise - coalesce(b.commission_paise, 0)),
		       coalesce(a.account_holder_name, ''), a.account_number_encrypted,
		       coalesce(a.ifsc_code, ''), coalesce(a.verified_name, ''), a.updated_at,
		       d.kyc_status, a.verified_at
		FROM bookings b
		JOIN drivers d ON d.id = b.driver_id
		LEFT JOIN driver_bank_accounts a ON a.driver_id = d.id
		WHERE b.paid_at IS NOT NULL AND b.payout_id IS NULL AND b.paid_at <= $1
		  AND b.paid_mode IS DISTINCT FROM 'cash' -- the customer paid the driver: MOJUD owes nothing
		GROUP BY d.id, d.name, d.phone_e164, d.kyc_status, a.driver_id
		ORDER BY 5 DESC`, asOf)
	if err != nil {
		return nil, fmt.Errorf("listing due payouts: %w", err)
	}
	defer rows.Close()
	out := []domain.PayoutDue{}
	for rows.Next() {
		var p domain.PayoutDue
		if err := rows.Scan(&p.DriverID, &p.DriverName, &p.DriverPhone, &p.Rides, &p.AmountPaise,
			&p.AccountHolderName, &p.AccountNumberEncrypted, &p.IFSCCode, &p.VerifiedName, &p.AccountUpdatedAt,
			&p.KYCStatus, &p.AccountVerifiedAt); err != nil {
			return nil, fmt.Errorf("listing due payouts: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// RecordPayout records one transfer to driverID covering every ride of
// theirs paid on or before asOf and not yet paid out, and stamps exactly
// those rides with it — in one transaction. [ErrNothingToPayOut] when there
// are none; [ErrPayoutMismatch] when they don't add up to expect.
func (r *PaymentRepository) RecordPayout(
	ctx context.Context, driverID, reference string, asOf, at time.Time, expect ExpectedPayout,
) (domain.DriverPayout, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Lock the rides so a concurrent payout can't claim them too, and keep
	// their ids: the stamp below must cover these rows and no others (a
	// payment committing after this read is for the next payout).
	ids, amount, err := lockDueRides(ctx, tx, driverID, asOf)
	if err != nil {
		return domain.DriverPayout{}, err
	}
	rides := len(ids)
	if rides == 0 || amount <= 0 {
		return domain.DriverPayout{}, ErrNothingToPayOut
	}
	if (expect.AmountPaise != nil && *expect.AmountPaise != amount) || (expect.Rides != nil && *expect.Rides != rides) {
		return domain.DriverPayout{}, fmt.Errorf("%w (now %d rides, %d paise)", ErrPayoutMismatch, rides, amount)
	}

	p := domain.DriverPayout{DriverID: driverID, AmountPaise: amount, Rides: rides, Reference: reference}
	if err := tx.QueryRow(ctx, `
		INSERT INTO driver_payouts (driver_id, amount_paise, rides, reference, created_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at`,
		driverID, amount, rides, reference, at).Scan(&p.ID, &p.CreatedAt); err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	tag, err := tx.Exec(ctx, `UPDATE bookings SET payout_id = $2 WHERE id = ANY($1::uuid[])`, ids, p.ID)
	if err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	if tag.RowsAffected() != int64(rides) {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: stamped %d rides, locked %d", tag.RowsAffected(), rides)
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.DriverPayout{}, fmt.Errorf("recording payout: %w", err)
	}
	return p, nil
}

// lockDueRides locks driverID's rides paid by asOf and not yet paid out,
// returning their ids and the driver's total share of them. A ride settled
// in cash is never part of a payout (the customer paid the driver); a
// waived one is — MOJUD pays the driver's share itself.
func lockDueRides(ctx context.Context, tx pgx.Tx, driverID string, asOf time.Time) ([]string, int64, error) {
	rows, err := tx.Query(ctx, `
		SELECT id::text, paid_paise - coalesce(commission_paise, 0)
		FROM bookings
		WHERE driver_id = $1 AND paid_at IS NOT NULL AND payout_id IS NULL AND paid_at <= $2
		  AND paid_mode IS DISTINCT FROM 'cash'
		FOR UPDATE`, driverID, asOf)
	if err != nil {
		return nil, 0, rideErr(err, ErrNothingToPayOut, "recording payout")
	}
	defer rows.Close()
	var (
		ids    []string
		amount int64
	)
	for rows.Next() {
		var (
			id    string
			share int64
		)
		if err := rows.Scan(&id, &share); err != nil {
			return nil, 0, fmt.Errorf("recording payout: %w", err)
		}
		ids, amount = append(ids, id), amount+share
	}
	if err := rows.Err(); err != nil {
		return nil, 0, rideErr(err, ErrNothingToPayOut, "recording payout")
	}
	return ids, amount, nil
}
