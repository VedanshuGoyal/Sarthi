package repository

import (
	"slices"
	"testing"
	"time"
)

func TestDriverDutyRepository_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewDriverDutyRepository(tx)
	driver := newTestDriver(t, ctx, tx)
	// Far ahead, so the dev DB's own rows never fall in these windows.
	t0 := time.Date(2099, 1, 1, 9, 0, 0, 0, time.UTC)
	lat, lng := 28.61, 77.23

	onDuty := func(since time.Time) []string {
		t.Helper()
		rows, err := repo.OnDuty(ctx, since)
		if err != nil {
			t.Fatalf("OnDuty: %v", err)
		}
		var ids []string
		for _, r := range rows {
			if r.DriverID == driver {
				if !r.Since.Equal(t0) || r.Lat == nil || *r.Lat != lat {
					t.Errorf("row = %+v, want on duty since t0 at %v", r, lat)
				}
				ids = append(ids, r.DriverID)
			}
		}
		return ids
	}
	lastSeen := func() time.Time {
		t.Helper()
		var at time.Time
		if err := tx.QueryRow(ctx, `SELECT last_seen_at FROM drivers WHERE id = $1`, driver).Scan(&at); err != nil {
			t.Fatalf("reading last_seen_at: %v", err)
		}
		return at
	}

	if err := repo.SaveDuty(ctx, driver, t0, &lat, &lng); err != nil {
		t.Fatalf("SaveDuty: %v", err)
	}
	// Heartbeats are written at most once a minute, and without a position
	// keep the last one.
	if err := repo.SaveDuty(ctx, driver, t0.Add(20*time.Second), nil, nil); err != nil {
		t.Fatalf("SaveDuty: %v", err)
	}
	if got := lastSeen(); !got.Equal(t0) {
		t.Errorf("last seen after a 20 s heartbeat = %v, want still t0", got)
	}
	if err := repo.SaveDuty(ctx, driver, t0.Add(time.Minute), nil, nil); err != nil {
		t.Fatalf("SaveDuty: %v", err)
	}
	if got := lastSeen(); !got.Equal(t0.Add(time.Minute)) {
		t.Errorf("last seen after a minute = %v, want t0+1m", got)
	}
	if got := onDuty(t0); !slices.Equal(got, []string{driver}) {
		t.Errorf("on duty = %v, want the driver", got)
	}

	// Silent past the cut: taken off duty, once.
	ids, err := repo.ExpireDuty(ctx, t0.Add(2*time.Minute))
	if err != nil || !slices.Contains(ids, driver) {
		t.Fatalf("ExpireDuty = %v, %v; want the driver", ids, err)
	}
	if ids, _ := repo.ExpireDuty(ctx, t0.Add(2*time.Minute)); slices.Contains(ids, driver) {
		t.Error("a driver already off duty was expired again")
	}
	if got := onDuty(t0); len(got) != 0 {
		t.Errorf("on duty after expiry = %v", got)
	}

	// Back on duty, then off by hand.
	if err := repo.SaveDuty(ctx, driver, t0, &lat, &lng); err != nil {
		t.Fatalf("SaveDuty: %v", err)
	}
	if err := repo.EndDuty(ctx, driver); err != nil {
		t.Fatalf("EndDuty: %v", err)
	}
	if got := onDuty(t0.Add(-time.Hour)); len(got) != 0 {
		t.Errorf("on duty after EndDuty = %v", got)
	}
}
