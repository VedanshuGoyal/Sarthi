package repository

import (
	"context"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// openBooking inserts a requested booking of userID's starting at start and
// returns its id.
func openBooking(t *testing.T, ctx context.Context, db DB, userID string, start time.Time) string {
	t.Helper()
	var id string
	if err := db.QueryRow(ctx, `
		INSERT INTO bookings (user_id, trip_type, details, scheduled_at, fare_paise)
		VALUES ($1, 'roundTrip', '{}', $2, 24000)
		RETURNING id`, userID, start).Scan(&id); err != nil {
		t.Fatalf("inserting booking: %v", err)
	}
	return id
}

// The watchdog's checks run once per booking: once marked, a booking stops
// being listed for that check, and a second mark is refused.
func TestRideWatchRepository_MarksEachCheckOnce_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewRideWatchRepository(tx)
	user := newTestUser(t, ctx, tx)
	// Far in the future, so other rows in the dev DB don't fall in the window.
	base := time.Date(2099, 1, 1, 10, 0, 0, 0, time.UTC)
	soon := openBooking(t, ctx, tx, user, base.Add(time.Hour))
	later := openBooking(t, ctx, tx, user, base.Add(3*time.Hour))

	due, err := repo.Unmarked(ctx, "realert_1h", domain.RideStatusRequested, base, base.Add(2*time.Hour), 10)
	if err != nil {
		t.Fatalf("Unmarked: %v", err)
	}
	if len(due) != 1 || due[0].ID != soon || due[0].UserID != user {
		t.Fatalf("due = %+v, want only the booking starting in the window", due)
	}

	for i, want := range []bool{true, false} {
		got, err := repo.Mark(ctx, soon, "realert_1h", base)
		if err != nil || got != want {
			t.Fatalf("Mark #%d = %v, %v; want %v", i+1, got, err, want)
		}
	}
	if due, _ := repo.Unmarked(ctx, "realert_1h", domain.RideStatusRequested, base, base.Add(4*time.Hour), 10); len(due) != 1 || due[0].ID != later {
		t.Errorf("after marking: due = %+v, want only the later booking", due)
	}
	// Another kind is its own check.
	if due, _ := repo.Unmarked(ctx, "no_driver_yet", domain.RideStatusRequested, base, base.Add(2*time.Hour), 10); len(due) != 1 {
		t.Errorf("another check: due = %d bookings, want 1", len(due))
	}
	if _, err := repo.Mark(ctx, "not-a-uuid", "realert_1h", base); err != ErrRideNotFound {
		t.Errorf("Mark on a bad id: err = %v, want ErrRideNotFound", err)
	}
}
