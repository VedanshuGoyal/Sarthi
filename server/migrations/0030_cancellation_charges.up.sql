-- 0030_cancellation_charges.up.sql
--
-- Cancellation charges (HUMAN REVIEW REQUIRED: payments). See
-- docs/features/cancellation-charges.md.
--
--   * bookings.cancellation_fee_paise — the fee charged when the customer
--     cancelled after the driver reached the pickup. NULL when the
--     cancellation was free. Such a booking is paid like a completed ride:
--     paid_at / paid_paise / commission_paise / payout_id, and it blocks the
--     customer's next booking until it is.
--
--   * bookings.booked_fare_paise — the fare as booked, kept when the
--     customer ended the trip early; fare_paise is then the charge for the
--     time used. NULL otherwise.
--
--   * bookings_user_unpaid_fee — serves "has this customer an unpaid fee?",
--     asked before every new booking alongside bookings_user_unpaid.
--
-- Additive only: nullable columns every existing row leaves NULL, a CHECK
-- they all pass, and an index on a small table. Safe on live data and
-- idempotent.

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS cancellation_fee_paise BIGINT,
    ADD COLUMN IF NOT EXISTS booked_fare_paise      BIGINT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bookings_cancellation_fee_check') THEN
        ALTER TABLE bookings ADD CONSTRAINT bookings_cancellation_fee_check
            CHECK (cancellation_fee_paise IS NULL
                   OR (cancellation_fee_paise > 0 AND status = 'cancelled'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS bookings_user_unpaid_fee
    ON bookings (user_id, cancelled_at)
    WHERE status = 'cancelled' AND cancellation_fee_paise IS NOT NULL AND paid_at IS NULL;
