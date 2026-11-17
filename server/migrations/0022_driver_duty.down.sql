-- 0022_driver_duty.down.sql

DROP INDEX IF EXISTS drivers_on_duty;

ALTER TABLE drivers
    DROP COLUMN IF EXISTS last_seen_at,
    DROP COLUMN IF EXISTS last_lng,
    DROP COLUMN IF EXISTS last_lat,
    DROP COLUMN IF EXISTS on_duty_at;
