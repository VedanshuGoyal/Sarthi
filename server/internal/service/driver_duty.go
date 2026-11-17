package service

import (
	"context"
	"log/slog"
	"time"

	"github.com/sarthi/server/internal/domain"
)

const (
	// dutySilence is how long an on-duty driver's app can stay silent before
	// the watchdog takes them off duty and tells them so. Rides are booked
	// at least 45 minutes ahead, so this is judged in hours, not seconds
	// (my estimate).
	dutySilence = 2 * time.Hour

	// restoreSeenWithin is how far back a driver must have been heard from
	// to be put back in presence at boot. Whether they're alerted directly
	// is still judged by presenceFresh against when they were last heard
	// from, not by the restart.
	restoreSeenWithin = time.Hour
)

// DutyStore persists drivers' on/off duty and last position
// (repository.DriverDutyRepository).
type DutyStore interface {
	SaveDuty(ctx context.Context, driverID string, at time.Time, lat, lng *float64) error
	EndDuty(ctx context.Context, driverID string) error
}

// DutyLister lists the drivers on duty heard from since a time.
type DutyLister interface {
	OnDuty(ctx context.Context, seenSince time.Time) ([]domain.DriverDuty, error)
}

// DutyExpirer takes silent drivers off duty, returning who.
type DutyExpirer interface {
	ExpireDuty(ctx context.Context, silentSince time.Time) ([]string, error)
}

// PresenceRestorer refills the presence index after a restart
// (memstore.DriverTracker).
type PresenceRestorer interface {
	Restore(driverID string, loc *domain.Location, seenAt time.Time) error
}

// DutyAlerter tells a driver the server took them off duty (NotifyService).
type DutyAlerter interface {
	DutyEnded(ctx context.Context, driverID string)
}

// RestorePresence puts back in presence every driver on duty in PostgreSQL
// who was heard from within restoreSeenWithin of now, as of when they were
// last heard from — so a deploy no longer forgets who is online. It returns
// how many it restored.
func RestorePresence(ctx context.Context, store DutyLister, presence PresenceRestorer, now time.Time) (int, error) {
	duties, err := store.OnDuty(ctx, now.Add(-restoreSeenWithin))
	if err != nil {
		return 0, err
	}
	n := 0
	for _, d := range duties {
		var loc *domain.Location
		if d.Lat != nil && d.Lng != nil {
			loc = &domain.Location{Lat: *d.Lat, Lng: *d.Lng}
		}
		if err := presence.Restore(d.DriverID, loc, d.LastSeenAt); err != nil {
			slog.WarnContext(ctx, "presence: restoring a driver failed", "driverId", d.DriverID, "error", err)
			continue
		}
		n++
	}
	return n, nil
}

// dutyWatch is the watchdog's duty check: who to take off duty, and how.
type dutyWatch struct {
	store    DutyExpirer
	presence DriverPresence
	alerts   DutyAlerter
}

// WatchDuty has the watchdog also take drivers off duty once their app has
// been silent for dutySilence: out of presence, off duty in PostgreSQL, and
// a push saying so.
func (w *RideWatchdog) WatchDuty(store DutyExpirer, presence DriverPresence, alerts DutyAlerter) {
	w.duty = &dutyWatch{store: store, presence: presence, alerts: alerts}
}

// expireDuty runs the duty check, returning how many drivers it took off.
func (w *RideWatchdog) expireDuty(ctx context.Context) int {
	if w.duty == nil {
		return 0
	}
	ids, err := w.duty.store.ExpireDuty(ctx, w.now().Add(-dutySilence))
	if err != nil {
		slog.WarnContext(ctx, "watchdog: ending silent drivers' duty failed", "error", err)
		return 0
	}
	for _, id := range ids {
		w.duty.presence.Remove(id)
		slog.InfoContext(ctx, "watchdog: driver taken off duty after silence", "driverId", id)
		w.duty.alerts.DutyEnded(ctx, id)
	}
	return len(ids)
}
