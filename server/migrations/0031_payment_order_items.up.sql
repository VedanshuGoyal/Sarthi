-- 0031_payment_order_items.up.sql
--
-- Carried dues (HUMAN REVIEW REQUIRED: payments). An unpaid ride or
-- cancellation fee no longer blocks the customer's next booking; it is
-- collected with their next payment instead. One checkout can so pay
-- several bookings:
--
--   * payment_order_items — the bookings a checkout pays and how much of it
--     is each one's. payment_orders.booking_id stays the booking the
--     customer tapped Pay on; its amount_paise is the items' sum. When the
--     order completes, each item's booking is marked paid with its own
--     amount and commission, so each driver is owed their own share.
--
-- Orders opened before this have exactly one item, their own booking and
-- amount; the backfill below writes it. Additive and idempotent; payment
-- orders are never deleted, so RESTRICT costs nothing.

CREATE TABLE IF NOT EXISTS payment_order_items (
    merchant_order_id TEXT   NOT NULL REFERENCES payment_orders (merchant_order_id) ON DELETE RESTRICT,
    booking_id        UUID   NOT NULL REFERENCES bookings (id) ON DELETE RESTRICT,
    amount_paise      BIGINT NOT NULL CHECK (amount_paise > 0),
    PRIMARY KEY (merchant_order_id, booking_id)
);

-- Serves "the orders that pay this booking".
CREATE INDEX IF NOT EXISTS payment_order_items_booking ON payment_order_items (booking_id);

INSERT INTO payment_order_items (merchant_order_id, booking_id, amount_paise)
SELECT merchant_order_id, booking_id, amount_paise FROM payment_orders
ON CONFLICT DO NOTHING;
