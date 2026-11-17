-- 0016_payment_checkout_token.up.sql
--
-- A second tap on "Pay" used to open a second PhonePe order while the first
-- was still payable, so a customer could pay a ride twice (a pending UPI
-- collect plus an intent payment). Keeping the SDK token of each order lets
-- Checkout hand the still-open order out again instead.
--
--   * checkout_token — what PhonePe's SDK opens the order with. NULL for
--     orders opened before this column existed; those are never reopened.
--
-- Adds a nullable column only, so existing rows are untouched.
-- Idempotent like every migration here (replayed on each local boot).

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS checkout_token TEXT;
