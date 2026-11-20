package repository

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// newTestUser inserts a customer through db and returns its id.
func newTestUser(t *testing.T, ctx context.Context, db DB) string {
	t.Helper()
	var id string
	phone := fmt.Sprintf("+9180%08d", time.Now().UnixNano()%100_000_000)
	if err := db.QueryRow(ctx, `
		INSERT INTO users (phone_e164, name, email, date_of_birth)
		VALUES ($1, 'Test Customer', 'customer@example.test', '1990-01-01')
		RETURNING id`, phone).Scan(&id); err != nil {
		t.Fatalf("inserting user: %v", err)
	}
	return id
}

// paidRide inserts a completed ride of driverID's that the customer paid
// fare for at paidAt, with MOJUD's cut; it returns the booking id.
func paidRide(t *testing.T, ctx context.Context, db DB, userID, driverID string, paidAt time.Time, fare, cut int64) string {
	t.Helper()
	var id string
	if err := db.QueryRow(ctx, `
		INSERT INTO bookings
		    (user_id, trip_type, details, status, driver_id, scheduled_at, fare_paise,
		     completed_at, paid_at, paid_paise, commission_paise)
		VALUES ($1, 'roundTrip', '{}', 'completed', $2, $3, $4, $3, $3, $4, $5)
		RETURNING id`, userID, driverID, paidAt, fare, cut).Scan(&id); err != nil {
		t.Fatalf("inserting paid ride: %v", err)
	}
	return id
}

// orderForPaidRide stores order o for a ride paidRide marked paid, as if the
// order had been opened before the payment landed (InsertOrder itself
// refuses a booking that's paid already).
func orderForPaidRide(t *testing.T, ctx context.Context, db DB, o domain.PaymentOrder) {
	t.Helper()
	var paidAt time.Time
	if err := db.QueryRow(ctx, `SELECT paid_at FROM bookings WHERE id = $1`, o.BookingID).Scan(&paidAt); err != nil {
		t.Fatalf("reading paid_at: %v", err)
	}
	if _, err := db.Exec(ctx, `UPDATE bookings SET paid_at = NULL WHERE id = $1`, o.BookingID); err != nil {
		t.Fatal(err)
	}
	if err := NewPaymentRepository(db).InsertOrder(ctx, o); err != nil {
		t.Fatalf("InsertOrder: %v", err)
	}
	if _, err := db.Exec(ctx, `UPDATE bookings SET paid_at = $2 WHERE id = $1`, o.BookingID, paidAt); err != nil {
		t.Fatal(err)
	}
}

func payoutOf(t *testing.T, ctx context.Context, db DB, bookingID string) string {
	t.Helper()
	var payout string
	if err := db.QueryRow(ctx, `SELECT coalesce(payout_id::text, '') FROM bookings WHERE id = $1`, bookingID).
		Scan(&payout); err != nil {
		t.Fatalf("reading payout_id: %v", err)
	}
	return payout
}

func TestPaymentRepository_OrderKeepsItsCheckoutToken_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewPaymentRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	booking := paidRide(t, ctx, tx, user, driver, time.Now(), 30000, 3900)
	expires := time.Now().Add(15 * time.Minute).Truncate(time.Microsecond)

	for _, o := range []domain.PaymentOrder{
		{MerchantOrderID: "MOJUD_test_tok", CheckoutToken: "sdk-token"},
		{MerchantOrderID: "MOJUD_test_old"}, // opened before tokens were kept
	} {
		o.BookingID, o.UserID, o.AmountPaise, o.ProviderOrderID, o.ExpiresAt = booking, user, 30000, "OMO1", expires
		orderForPaidRide(t, ctx, tx, o)
	}
	pending, err := repo.PendingForBooking(ctx, booking)
	if err != nil || len(pending) != 2 {
		t.Fatalf("PendingForBooking = %v, %v", pending, err)
	}
	tokens := map[string]string{}
	for _, o := range pending {
		tokens[o.MerchantOrderID] = o.CheckoutToken
		if !o.ExpiresAt.Equal(expires) {
			t.Errorf("%s expires %v, want %v", o.MerchantOrderID, o.ExpiresAt, expires)
		}
	}
	if tokens["MOJUD_test_tok"] != "sdk-token" || tokens["MOJUD_test_old"] != "" {
		t.Errorf("tokens = %v", tokens)
	}
}

func TestPaymentRepository_DuePayoutsCarriesTheHoldInputs_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewPaymentRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	asOf := time.Now()
	paidRide(t, ctx, tx, user, driver, asOf.Add(-time.Hour), 10000, 1300)
	if _, err := tx.Exec(ctx, `UPDATE drivers SET kyc_status = 'verified' WHERE id = $1`, driver); err != nil {
		t.Fatalf("verifying driver: %v", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO driver_bank_accounts
		    (driver_id, account_holder_name, account_number_encrypted, account_number_last4, ifsc_code,
		     verified_at, verified_name)
		VALUES ($1, 'Typed Name', '\x01'::bytea, '7890', 'HDFC0001234', now(), 'BANK NAME')`, driver); err != nil {
		t.Fatalf("inserting bank account: %v", err)
	}

	due, err := repo.DuePayouts(ctx, asOf)
	if err != nil {
		t.Fatalf("DuePayouts: %v", err)
	}
	for _, d := range due {
		if d.DriverID != driver {
			continue
		}
		if d.KYCStatus != "verified" || d.AccountVerifiedAt == nil || d.VerifiedName != "BANK NAME" ||
			d.AccountUpdatedAt == nil || d.Rides != 1 || d.AmountPaise != 8700 {
			t.Errorf("due = %+v", d)
		}
		return
	}
	t.Fatalf("driver %s not listed in %+v", driver, due)
}

func TestPaymentRepository_RecordPayout_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewPaymentRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)

	asOf := time.Date(2026, 11, 10, 12, 0, 0, 0, time.UTC)
	r1 := paidRide(t, ctx, tx, user, driver, asOf.Add(-2*time.Hour), 10000, 1300) // share 8700
	r2 := paidRide(t, ctx, tx, user, driver, asOf, 5000, 650)                     // share 4350, on the boundary
	late := paidRide(t, ctx, tx, user, driver, asOf.Add(time.Minute), 7000, 910)  // after the list was read
	at := asOf.Add(time.Hour)

	// What the list showed no longer adds up: refused, nothing stamped.
	stale := ExpectedPayout{AmountPaise: new(int64(8700)), Rides: new(1)}
	if _, err := repo.RecordPayout(ctx, driver, "UTR1", asOf, at, stale); !errors.Is(err, ErrPayoutMismatch) {
		t.Fatalf("stale expectation: err = %v, want ErrPayoutMismatch", err)
	}
	if payoutOf(t, ctx, tx, r1) != "" {
		t.Fatal("a refused payout stamped a ride")
	}

	want := ExpectedPayout{AmountPaise: new(int64(13050)), Rides: new(2)}
	p, err := repo.RecordPayout(ctx, driver, "UTR1", asOf, at, want)
	if err != nil {
		t.Fatalf("RecordPayout: %v", err)
	}
	if p.Rides != 2 || p.AmountPaise != 13050 {
		t.Errorf("payout = %d rides, %d paise; want 2, 13050", p.Rides, p.AmountPaise)
	}
	for _, id := range []string{r1, r2} {
		if got := payoutOf(t, ctx, tx, id); got != p.ID {
			t.Errorf("ride %s payout_id = %q, want %q", id, got, p.ID)
		}
	}
	if got := payoutOf(t, ctx, tx, late); got != "" {
		t.Errorf("a ride paid after asOf was stamped with %q", got)
	}

	// Everything up to asOf is paid out now; no expectation is the old call.
	if _, err := repo.RecordPayout(ctx, driver, "UTR2", asOf, at, ExpectedPayout{}); !errors.Is(err, ErrNothingToPayOut) {
		t.Fatalf("second payout: err = %v, want ErrNothingToPayOut", err)
	}
	p2, err := repo.RecordPayout(ctx, driver, "UTR3", at, at, ExpectedPayout{})
	if err != nil || p2.Rides != 1 || p2.AmountPaise != 6090 {
		t.Fatalf("later payout = %+v, %v; want the late ride's 6090", p2, err)
	}
}
