-- 0013_payments.down.sql

DROP INDEX IF EXISTS bookings_unpaid_out;

ALTER TABLE bookings
    DROP COLUMN IF EXISTS payout_id,
    DROP COLUMN IF EXISTS payment_order_id,
    DROP COLUMN IF EXISTS commission_paise,
    DROP COLUMN IF EXISTS paid_paise,
    DROP COLUMN IF EXISTS paid_at;

DROP TABLE IF EXISTS driver_payouts;
DROP TABLE IF EXISTS payment_orders;
