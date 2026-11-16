package repository

import (
	"testing"
	"time"
)

func TestBookingRepository_DriverBusyElsewhere_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewBookingRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	ride := func(status string) string {
		var id string
		if err := tx.QueryRow(ctx, `
			INSERT INTO bookings (user_id, trip_type, details, status, driver_id, scheduled_at)
			VALUES ($1, 'roundTrip', '{}', $2, $3, $4) RETURNING id`,
			user, status, driver, time.Now()).Scan(&id); err != nil {
			t.Fatalf("inserting ride: %v", err)
		}
		return id
	}
	next := ride("accepted")
	busy := func() bool {
		t.Helper()
		b, err := repo.DriverBusyElsewhere(ctx, driver, next)
		if err != nil {
			t.Fatalf("DriverBusyElsewhere: %v", err)
		}
		return b
	}

	ride("completed")
	if busy() {
		t.Error("a finished ride counts as busy")
	}
	current := ride("in_progress")
	if !busy() {
		t.Error("a ride in progress elsewhere doesn't count as busy")
	}
	if b, err := repo.DriverBusyElsewhere(ctx, driver, current); err != nil || b {
		t.Errorf("asked about the ride in progress itself: %v, %v; want false", b, err)
	}
}
