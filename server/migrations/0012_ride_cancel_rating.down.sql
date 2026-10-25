-- 0012_ride_cancel_rating.down.sql
ALTER TABLE bookings
    DROP COLUMN IF EXISTS cancelled_at,
    DROP COLUMN IF EXISTS cancelled_by,
    DROP COLUMN IF EXISTS cancel_reason,
    DROP COLUMN IF EXISTS driver_rating,
    DROP COLUMN IF EXISTS driver_rating_note,
    DROP COLUMN IF EXISTS customer_rating,
    DROP COLUMN IF EXISTS customer_rating_note;
