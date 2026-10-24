-- 0009_booking_rides.down.sql
DROP TABLE IF EXISTS booking_declines;

DROP INDEX IF EXISTS bookings_driver_scheduled;
DROP INDEX IF EXISTS bookings_open_scheduled;

ALTER TABLE bookings
    DROP COLUMN IF EXISTS status,
    DROP COLUMN IF EXISTS driver_id,
    DROP COLUMN IF EXISTS scheduled_at,
    DROP COLUMN IF EXISTS fare_paise,
    DROP COLUMN IF EXISTS fare_estimated,
    DROP COLUMN IF EXISTS accepted_at,
    DROP COLUMN IF EXISTS arrived_at,
    DROP COLUMN IF EXISTS started_at,
    DROP COLUMN IF EXISTS completed_at;
