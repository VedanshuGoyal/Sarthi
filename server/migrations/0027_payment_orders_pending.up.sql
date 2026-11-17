-- 0027_payment_orders_pending.up.sql
--
-- Serves the 2-minute payment sweep and the admin "needs attention" list
-- (orders still pending after a day; HUMAN REVIEW REQUIRED: payments): both
-- look for pending orders by age.
--
-- Index only. payment_orders is small (empty in production today), so a
-- plain CREATE INDEX is instant. Idempotent like every migration here.

CREATE INDEX IF NOT EXISTS payment_orders_pending_created
    ON payment_orders (created_at)
    WHERE state = 'pending';
