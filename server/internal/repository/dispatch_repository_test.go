package repository

import (
	"fmt"
	"slices"
	"testing"
	"time"
)

// A ride request's fallback reaches verified drivers with the app
// installed — not ones still in KYC, nor ones with no install.
func TestPushTokenRepository_VerifiedDriversWithTokens_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewPushTokenRepository(tx)
	verified, pending, noApp := newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx)
	if _, err := tx.Exec(ctx, `UPDATE drivers SET kyc_status = 'verified' WHERE id = ANY($1::uuid[])`,
		[]string{verified, noApp}); err != nil {
		t.Fatalf("verifying: %v", err)
	}
	tag := fmt.Sprint(time.Now().UnixNano())
	for _, id := range []string{verified, pending} {
		if err := repo.SaveForDriver(ctx, id, "tok-"+id+"-"+tag); err != nil {
			t.Fatalf("SaveForDriver: %v", err)
		}
	}
	if err := repo.SaveForDriver(ctx, verified, "tok-2-"+tag); err != nil {
		t.Fatalf("SaveForDriver: %v", err)
	}

	ids, err := repo.VerifiedDriversWithTokens(ctx, 10_000)
	if err != nil {
		t.Fatalf("VerifiedDriversWithTokens: %v", err)
	}
	if !slices.Contains(ids, verified) || slices.Contains(ids, pending) || slices.Contains(ids, noApp) {
		t.Errorf("listed %v; want %s and neither %s (pending) nor %s (no app)", ids, verified, pending, noApp)
	}
	if n := len(slices.DeleteFunc(slices.Clone(ids), func(id string) bool { return id != verified })); n != 1 {
		t.Errorf("%s listed %d times, want once for two installs", verified, n)
	}
	// Newest install first.
	if ids[0] != verified {
		t.Errorf("first = %s, want the driver who registered an install just now", ids[0])
	}
}

// Only a ride its driver is waiting at the pickup of can be closed as a
// no-show, and it lands cancelled by "no_show" with no start code left.
func TestDriverRideRepository_NoShow_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewDriverRideRepository(tx)
	user, driver, other := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx)
	start := time.Date(2099, 1, 1, 10, 0, 0, 0, time.UTC)
	ride := openBooking(t, ctx, tx, user, start)

	if _, err := repo.Accept(ctx, ride, driver, start.Add(-2*time.Hour), "1234"); err != nil {
		t.Fatalf("Accept: %v", err)
	}
	if _, err := repo.NoShow(ctx, ride, driver, start, "x"); err != ErrRideStateConflict {
		t.Errorf("no-show before arriving: err = %v, want ErrRideStateConflict", err)
	}
	if _, err := repo.Advance(ctx, ride, driver, "accepted", "arrived", start); err != nil {
		t.Fatalf("Advance: %v", err)
	}
	if _, err := repo.NoShow(ctx, ride, other, start, "x"); err != ErrRideStateConflict {
		t.Errorf("another driver: err = %v, want ErrRideStateConflict", err)
	}
	at := start.Add(15 * time.Minute)
	rb, err := repo.NoShow(ctx, ride, driver, at, "The driver waited at the pickup until 10:15 AM")
	if err != nil {
		t.Fatalf("NoShow: %v", err)
	}
	b := rb.Booking
	if b.Status != "cancelled" || b.CancelledBy != "no_show" || b.StartOTP != "" ||
		b.CancelledAt == nil || !b.CancelledAt.Equal(at) || b.DriverID != driver || rb.Customer.Name == "" {
		t.Errorf("booking = %+v", rb)
	}
	if _, err := repo.NoShow(ctx, ride, driver, at, "x"); err != ErrRideStateConflict {
		t.Errorf("second no-show: err = %v, want ErrRideStateConflict", err)
	}
}

func TestDriverRideRepository_DeclinedBy_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewDriverRideRepository(tx)
	user, a, b := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx)
	ride := openBooking(t, ctx, tx, user, time.Date(2099, 1, 1, 10, 0, 0, 0, time.UTC))

	if got, err := repo.DeclinedBy(ctx, ride); err != nil || len(got) != 0 {
		t.Fatalf("before any decline: %v, %v", got, err)
	}
	for _, id := range []string{a, a, b} {
		if err := repo.Decline(ctx, ride, id); err != nil {
			t.Fatalf("Decline: %v", err)
		}
	}
	got, err := repo.DeclinedBy(ctx, ride)
	slices.Sort(got)
	want := []string{a, b}
	slices.Sort(want)
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("DeclinedBy = %v, %v; want %v", got, err, want)
	}
}
