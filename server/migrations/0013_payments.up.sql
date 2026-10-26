-- 0013_payments.up.sql
--
-- Customers pay MOJUD for a completed ride by UPI through PhonePe's payment
-- gateway; MOJUD keeps its commission and pays each driver the rest by bank
-- transfer, in weekly batches.
--
--   * payment_orders — one row per checkout the customer opens. PhonePe
--     names an order by our merchant_order_id; its state only ever moves
--     pending -> completed | failed, and only after PhonePe's order-status
--     API says so (a webhook is just a nudge to go and ask).
--
--   * bookings.paid_* — set once, by the first order that completes. A
--     second completed order for an already-paid ride is left on its row for
--     a manual refund. commission_paise is MOJUD's cut, fixed at the
--     commission rate in force when the payment landed.
--
--   * driver_payouts — one bank transfer to a driver. Every paid ride it
--     covers points at it through bookings.payout_id; a ride with paid_at
--     set and no payout_id is still owed to its driver.
--
-- Idempotent like every migration here (replayed on each local boot).

CREATE TABLE IF NOT EXISTS payment_orders (
    merchant_order_id TEXT PRIMARY KEY,
    booking_id        UUID        NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_paise      BIGINT      NOT NULL CHECK (amount_paise > 0),
    provider_order_id TEXT        NOT NULL,
    state             TEXT        NOT NULL DEFAULT 'pending', -- pending | completed | failed
    transaction_id    TEXT,
    payment_mode      TEXT,
    utr               TEXT,
    expires_at        TIMESTAMPTZ NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Serves "this ride's orders, newest first".
CREATE INDEX IF NOT EXISTS payment_orders_booking_created
    ON payment_orders (booking_id, created_at DESC);

CREATE TABLE IF NOT EXISTS driver_payouts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id    UUID        NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,
    amount_paise BIGINT      NOT NULL CHECK (amount_paise > 0),
    rides        INT         NOT NULL CHECK (rides > 0),
    reference    TEXT        NOT NULL, -- the bank's UTR / transfer reference
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS driver_payouts_driver_created
    ON driver_payouts (driver_id, created_at DESC);

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS paid_at           TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS paid_paise        BIGINT,
    ADD COLUMN IF NOT EXISTS commission_paise  BIGINT,
    ADD COLUMN IF NOT EXISTS payment_order_id  TEXT REFERENCES payment_orders(merchant_order_id),
    ADD COLUMN IF NOT EXISTS payout_id         UUID REFERENCES driver_payouts(id);

-- Serves the payouts list: paid rides not yet paid out, per driver.
CREATE INDEX IF NOT EXISTS bookings_unpaid_out
    ON bookings (driver_id, paid_at)
    WHERE paid_at IS NOT NULL AND payout_id IS NULL;
