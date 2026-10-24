-- 0009_booking_rides.up.sql
--
-- Turns a confirmed booking into a ride a driver can take. Until now a booking
-- was write-once; these columns carry it through the driver app's lifecycle:
--
--   requested -> accepted -> arrived -> in_progress -> completed
--
-- A driver who releases an accepted ride (before starting it) hands it back to
-- `requested` with driver_id cleared, so another driver can pick it up.
--
-- scheduled_at and fare_paise are lifted out of the JSONB details so the
-- driver's lists can filter and sort on them, and earnings can be summed in
-- SQL. Money is integer paise, never floats.
--
-- Like every migration here this is replayed on each boot, so every statement
-- is idempotent (IF NOT EXISTS, and the backfill only touches NULL rows).

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS status        TEXT NOT NULL DEFAULT 'requested',
    ADD COLUMN IF NOT EXISTS driver_id     UUID REFERENCES drivers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS scheduled_at  TIMESTAMPTZ,
    -- What the driver sees as the trip's fare. Round trips carry the fare the
    -- customer was quoted; one-way and multi-stop trips are estimated by the
    -- server from their duration (fare_estimated = true).
    ADD COLUMN IF NOT EXISTS fare_paise     BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS fare_estimated BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS accepted_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS arrived_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS started_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completed_at  TIMESTAMPTZ;

-- Backfill scheduled_at for bookings made before this migration. The customer
-- app sends a local (IST) wall-clock time with no offset, e.g.
-- "2026-10-24T13:30:00.000"; a value that does carry one (Z or +hh:mm) is
-- read as given.
UPDATE bookings
SET scheduled_at = CASE
        WHEN details->>'scheduledAt' ~ '(Z|[+-][0-9]{2}:?[0-9]{2})$'
            THEN (details->>'scheduledAt')::timestamptz
        ELSE (details->>'scheduledAt')::timestamp AT TIME ZONE 'Asia/Kolkata'
    END
WHERE scheduled_at IS NULL
  AND details ? 'scheduledAt';

-- Backfill the round-trip fare (whole rupees in the details) as paise.
UPDATE bookings
SET fare_paise = ((details->>'fare')::numeric * 100)::bigint
WHERE fare_paise = 0
  AND trip_type = 'roundTrip'
  AND details ? 'fare';

-- Serves the open-requests feed: unassigned rides, soonest first.
CREATE INDEX IF NOT EXISTS bookings_open_scheduled
    ON bookings (scheduled_at)
    WHERE status = 'requested';

-- Serves a driver's own rides list and earnings sums.
CREATE INDEX IF NOT EXISTS bookings_driver_scheduled
    ON bookings (driver_id, scheduled_at DESC)
    WHERE driver_id IS NOT NULL;

-- Requests a driver has swiped away, so their feed stops showing them. Also
-- written when a driver releases a ride they accepted, so it doesn't bounce
-- straight back into their own feed.
CREATE TABLE IF NOT EXISTS booking_declines (
    booking_id  UUID        NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    driver_id   UUID        NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    declined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (booking_id, driver_id)
);
