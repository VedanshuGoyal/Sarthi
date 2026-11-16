package repository

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
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

func payoutOf(t *testing.T, ctx context.Context, db DB, bookingID string) string {
	t.Helper()
	var payout string
	if err := db.QueryRow(ctx, `SELECT coalesce(payout_id::text, '') FROM bookings WHERE id = $1`, bookingID).
		Scan(&payout); err != nil {
		t.Fatalf("reading payout_id: %v", err)
	}
	return payout
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
