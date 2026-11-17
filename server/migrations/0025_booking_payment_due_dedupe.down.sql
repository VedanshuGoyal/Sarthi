-- 0025_booking_payment_due_dedupe.down.sql
--
-- Drops the hand-settlement marker and the idempotency key. A ride settled
-- by hand keeps paid_at (it stays paid, with nothing owed to its driver);
-- only the record of how is lost.

DROP INDEX IF EXISTS bookings_user_unpaid;
DROP INDEX IF EXISTS bookings_user_idempotency_key;

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_paid_mode_check;

ALTER TABLE bookings
    DROP COLUMN IF EXISTS idempotency_key,
    DROP COLUMN IF EXISTS paid_note,
    DROP COLUMN IF EXISTS paid_mode;
