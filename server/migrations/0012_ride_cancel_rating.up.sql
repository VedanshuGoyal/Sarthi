-- 0012_ride_cancel_rating.up.sql
--
-- Two additions to a booking's life, both written once:
--
--   * Customer cancellation. A customer may cancel any time before the trip
--     starts (requested, accepted or arrived). The row moves to 'cancelled'
--     and keeps its driver_id, so the driver who had it still sees it — as
--     cancelled — in their rides list. cancelled_by names who cancelled
--     ('customer'); cancel_reason is the reason the customer picked, if any.
--
--   * Ratings, one per side, once the ride is completed: driver_rating is the
--     1–5 stars the customer gave the driver, customer_rating the stars the
--     driver gave the customer, each with an optional note. A driver's (or
--     customer's) average is the mean over their rated rides.
--
-- Idempotent like every migration here (replayed on each local boot).

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS cancelled_at         TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS cancelled_by         TEXT,
    ADD COLUMN IF NOT EXISTS cancel_reason        TEXT,
    ADD COLUMN IF NOT EXISTS driver_rating        SMALLINT CHECK (driver_rating BETWEEN 1 AND 5),
    ADD COLUMN IF NOT EXISTS driver_rating_note   TEXT,
    ADD COLUMN IF NOT EXISTS customer_rating      SMALLINT CHECK (customer_rating BETWEEN 1 AND 5),
    ADD COLUMN IF NOT EXISTS customer_rating_note TEXT;
