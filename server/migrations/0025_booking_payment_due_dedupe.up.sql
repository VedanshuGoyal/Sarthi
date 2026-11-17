-- 0025_booking_payment_due_dedupe.up.sql
--
-- Money and ops (HUMAN REVIEW REQUIRED: payments):
--
--   * bookings.paid_mode / paid_note — a completed ride MOJUD settled by
--     hand from the back office, without the gateway: 'cash' (the customer
--     paid the driver directly) or 'waived' (nobody pays). Such a ride gets
--     paid_at like a gateway payment but paid_paise = commission_paise = 0,
--     so it never adds to what MOJUD owes the driver. NULL for gateway
--     payments (payment_order_id names the order) and unpaid rides.
--
--   * bookings.idempotency_key — the customer app's per-attempt key
--     (Idempotency-Key header). A retried submit returns the booking the
--     first one made instead of opening a second request.
--
--   * bookings_user_unpaid — serves "has this customer an unpaid ride?",
--     asked before every new booking.
--
-- Additive only: nullable columns, a CHECK every existing row passes (all
-- NULL), and indexes on a small table. Safe on live data; idempotent like
-- every migration here (replayed on each local boot).

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS paid_mode       TEXT,
    ADD COLUMN IF NOT EXISTS paid_note       TEXT,
    ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bookings_paid_mode_check') THEN
        ALTER TABLE bookings ADD CONSTRAINT bookings_paid_mode_check
            CHECK (paid_mode IS NULL OR paid_mode IN ('cash', 'waived'));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS bookings_user_idempotency_key
    ON bookings (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS bookings_user_unpaid
    ON bookings (user_id, completed_at)
    WHERE status = 'completed' AND paid_at IS NULL;
