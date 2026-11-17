-- 0030_cancellation_charges.down.sql
--
-- Drops the fee and booked-fare columns. A fee already charged is forgotten
-- (its booking stays cancelled; if it was paid, paid_at and the payout
-- columns keep the money trail). A trip ended early keeps its charged fare.

DROP INDEX IF EXISTS bookings_user_unpaid_fee;

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_cancellation_fee_check;

ALTER TABLE bookings
    DROP COLUMN IF EXISTS booked_fare_paise,
    DROP COLUMN IF EXISTS cancellation_fee_paise;
