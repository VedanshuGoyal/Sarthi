-- 0021_booking_events.up.sql
--
-- Things that happened to a booking outside its status columns, written by
-- the ride watchdog (service/ride_watchdog.go): "no driver yet" and "no
-- driver found" pushes, re-alerts to drivers, the hour-before reminders,
-- and the ops alerts for a late driver or an overrunning ride.
--
--   * booking_events — one row per (booking, kind). The unique pair is what
--     makes the watchdog idempotent: it inserts the row first and only acts
--     if the insert went in, so a restart or a second pass never repeats a
--     push. detail is free-form context for ops.
--   * bookings_status_scheduled — the watchdog's per-minute scans read
--     bookings by status and start time.
--
-- New table and index only; no existing row changes. Safe on prod data.
-- Idempotent like every migration here (replayed on each local boot).

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL PRIMARY KEY,
    booking_id UUID        NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    kind       TEXT        NOT NULL CHECK (kind <> ''),
    detail     JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (booking_id, kind)
);

CREATE INDEX IF NOT EXISTS bookings_status_scheduled
    ON bookings (status, scheduled_at);
