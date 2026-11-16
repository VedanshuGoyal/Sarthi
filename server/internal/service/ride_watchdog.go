package service

import (
	"context"
	"log/slog"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// watchEvery is how often the ride watchdog looks for bookings due a check.
const watchEvery = time.Minute

// watchBatch caps how many bookings one check handles per pass; the rest
// wait a minute.
const watchBatch = 100

// Booking event kinds the watchdog writes, one of each per booking at most.
const (
	eventRealert3h   = "realert_3h"    // drivers alerted again, 3 h before start
	eventRealert1h   = "realert_1h"    // and 1 h before
	eventNoDriverYet = "no_driver_yet" // customer told: still looking, 1 h before
	eventNoDriver    = "no_driver"     // customer told: nobody took it, at close
	eventReminder    = "reminder_1h"   // driver and customer reminded, 1 h before
	eventLateArrival = "late_arrival"  // ops told: driver not there 15 min after start
	eventRideOverrun = "ride_overrun"  // ops told: ride 3 h past its planned end
)

// realertSettleTime is how long a request must have been open before a
// re-alert: one booked more recently was only just alerted.
const realertSettleTime = 30 * time.Minute

// RideWatchStore is the slice of persistence the watchdog needs
// (repository.RideWatchRepository).
type RideWatchStore interface {
	// Unmarked returns up to limit bookings in status starting in (from,
	// to], soonest first, with no kind event yet.
	Unmarked(ctx context.Context, kind string, status domain.RideStatus, from, to time.Time, limit int) ([]domain.Booking, error)
	// Mark records kind for bookingID, reporting false if it already was.
	Mark(ctx context.Context, bookingID, kind string, at time.Time) (bool, error)
}

// WatchAlerter sends the watchdog's pushes (NotifyService). Each call
// returns at once; the pushes go out in the background.
type WatchAlerter interface {
	// RealertDrivers sends open booking b's "new ride request" again.
	RealertDrivers(ctx context.Context, b domain.Booking, plan tripPlan)
	// NoDriverYet tells the customer nobody has taken b yet.
	NoDriverYet(ctx context.Context, b domain.Booking, plan tripPlan)
	// NoDriverFound tells the customer b closed with no driver.
	NoDriverFound(ctx context.Context, b domain.Booking, plan tripPlan)
	// RideReminder reminds b's driver and customer that it starts soon.
	RideReminder(ctx context.Context, b domain.Booking, plan tripPlan)
}

// watchCheck is one thing the watchdog looks for: bookings in status that
// fall due at offset at from their start (or, with fromEnd, from their
// planned end) and stay worth acting on until offset until. Bookings that
// reached status less than settle before falling due are left out.
type watchCheck struct {
	kind      string
	status    domain.RideStatus
	at, until time.Duration
	fromEnd   bool
	settle    time.Duration
	act       func(ctx context.Context, b domain.Booking, plan tripPlan)
}

// RideWatchdog watches bookings between booking and completion, where
// nothing else looks: it re-alerts drivers about rides nobody has taken,
// tells the customer when no driver has turned up yet and when none was
// found, reminds both sides an hour before a ride, and logs an ERROR for
// ops (which the Telegram watchdog forwards) when a driver is late or a ride
// runs hours over.
//
// It runs over Postgres every minute and is idempotent through
// booking_events: a check is recorded before it is acted on, so a restart
// or a slow pass never sends the same push twice. A check missed while the
// server was down still runs once it is back, while it's worth anything.
type RideWatchdog struct {
	store  RideWatchStore
	alerts WatchAlerter
	now    func() time.Time
	checks []watchCheck
}

// NewRideWatchdog wires the watchdog to its store and the pushes it sends.
func NewRideWatchdog(store RideWatchStore, alerts WatchAlerter) *RideWatchdog {
	w := &RideWatchdog{store: store, alerts: alerts, now: time.Now}
	w.checks = []watchCheck{
		{
			kind: eventRealert3h, status: domain.RideStatusRequested,
			at: -3 * time.Hour, until: -time.Hour, settle: realertSettleTime,
			act: alerts.RealertDrivers,
		},
		{
			kind: eventRealert1h, status: domain.RideStatusRequested,
			at: -time.Hour, until: -acceptCutoff, settle: realertSettleTime,
			act: alerts.RealertDrivers,
		},
		{
			kind: eventNoDriverYet, status: domain.RideStatusRequested,
			at: -time.Hour, until: -acceptCutoff,
			act: func(ctx context.Context, b domain.Booking, plan tripPlan) {
				slog.ErrorContext(ctx, "watchdog: no driver yet, 1 h before start; find one before it closes",
					"bookingId", b.ID, "scheduledAt", plan.ScheduledAt, "closesAt", plan.ScheduledAt.Add(-acceptCutoff))
				alerts.NoDriverYet(ctx, b, plan)
			},
		},
		{
			kind: eventNoDriver, status: domain.RideStatusRequested,
			at: -acceptCutoff, until: time.Hour,
			act: func(ctx context.Context, b domain.Booking, plan tripPlan) {
				slog.ErrorContext(ctx, "watchdog: ride request closed with no driver",
					"bookingId", b.ID, "scheduledAt", plan.ScheduledAt)
				alerts.NoDriverFound(ctx, b, plan)
			},
		},
		{
			kind: eventReminder, status: domain.RideStatusAccepted,
			at: -time.Hour, until: 0,
			act: alerts.RideReminder,
		},
		{
			kind: eventLateArrival, status: domain.RideStatusAccepted,
			at: 15 * time.Minute, until: 24 * time.Hour,
			act: func(ctx context.Context, b domain.Booking, plan tripPlan) {
				slog.ErrorContext(ctx, "watchdog: driver not at the pickup 15 min after start; call them",
					"bookingId", b.ID, "driverId", b.DriverID, "scheduledAt", plan.ScheduledAt)
			},
		},
		{
			kind: eventRideOverrun, status: domain.RideStatusInProgress,
			at: 3 * time.Hour, until: 7 * 24 * time.Hour, fromEnd: true,
			act: func(ctx context.Context, b domain.Booking, plan tripPlan) {
				slog.ErrorContext(ctx, "watchdog: ride still in progress 3 h past its planned end; check on it",
					"bookingId", b.ID, "driverId", b.DriverID, "plannedEnd", plan.EndsAt())
			},
		},
	}
	return w
}

// Run checks every watchEvery, starting now, until ctx ends.
func (w *RideWatchdog) Run(ctx context.Context) {
	t := time.NewTicker(watchEvery)
	defer t.Stop()
	for {
		w.Tick(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// Tick makes one pass over every check and returns how many bookings it
// acted on.
func (w *RideWatchdog) Tick(ctx context.Context) int {
	acted := 0
	for _, c := range w.checks {
		acted += w.run(ctx, c)
	}
	return acted
}

// maxPlannedDuration bounds how long after its start a ride can be planned
// to end, so a fromEnd check knows how far back to look: twice the longest
// round-trip hire.
const maxPlannedDuration = 2 * maxHireHours * time.Hour

func (w *RideWatchdog) run(ctx context.Context, c watchCheck) int {
	now := w.now()
	// Due when start+at <= now < start+until, so start is in (now-until,
	// now-at]. A check timed from the end looks back by the longest plan
	// and forward by the shortest (an hour, see tripPlan.Duration).
	from, to := now.Add(-c.until), now.Add(-c.at)
	if c.fromEnd {
		from, to = from.Add(-maxPlannedDuration), to.Add(-time.Hour)
	}
	due, err := w.store.Unmarked(ctx, c.kind, c.status, from, to, watchBatch)
	if err != nil {
		slog.WarnContext(ctx, "watchdog: listing bookings failed", "check", c.kind, "error", err)
		return 0
	}
	acted := 0
	for _, b := range due {
		plan, err := planOf(b)
		if err != nil {
			continue
		}
		anchor := plan.ScheduledAt
		if c.fromEnd {
			anchor = plan.EndsAt()
		}
		dueAt := anchor.Add(c.at)
		if now.Before(dueAt) || !now.Before(anchor.Add(c.until)) {
			continue
		}
		// Only bookings already in this state when the check fell due: a
		// request made 40 minutes before its start was never "open an hour
		// before", and one booked a minute ago was only just alerted.
		if inStatusSince(b).After(dueAt.Add(-c.settle)) {
			continue
		}
		marked, err := w.store.Mark(ctx, b.ID, c.kind, now)
		if err != nil {
			slog.WarnContext(ctx, "watchdog: recording check failed", "check", c.kind, "bookingId", b.ID, "error", err)
			continue
		}
		if !marked {
			continue
		}
		slog.InfoContext(ctx, "watchdog: check due", "check", c.kind, "bookingId", b.ID)
		c.act(ctx, b, plan)
		acted++
	}
	return acted
}

// inStatusSince is when b reached the status it's in, as far as the checks
// need: accepted when a driver took it, otherwise when it was booked.
func inStatusSince(b domain.Booking) time.Time {
	if b.Status == domain.RideStatusAccepted && b.AcceptedAt != nil {
		return *b.AcceptedAt
	}
	return b.CreatedAt
}
