-- 0022_driver_duty.up.sql
--
-- "On duty" lived only in the server's memory: every deploy or restart
-- forgot who was online until their app next reported in, and nothing
-- noticed a driver whose app had gone quiet for good. Duty is now kept on
-- the driver's row; memory is rebuilt from it at boot.
--
--   * on_duty_at   — when the driver went on duty; NULL when off duty.
--   * last_lat/lng — their last reported position (either may be NULL
--                    when the app had no GPS fix).
--   * last_seen_at — when their app last reported in while on duty,
--                    written at most about once a minute.
--
-- The ride watchdog takes a driver off duty, with a push, after long
-- silence; drivers_on_duty serves that scan and the boot rebuild.
--
-- Nullable columns with no default and no backfill: every existing driver
-- starts off duty, as they effectively are after a deploy today. Safe on
-- prod data. Idempotent like every migration here.

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS on_duty_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_lat     DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS last_lng     DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS drivers_on_duty
    ON drivers (last_seen_at)
    WHERE on_duty_at IS NOT NULL;
