-- 0016_payment_checkout_token.down.sql

ALTER TABLE payment_orders
    DROP COLUMN IF EXISTS checkout_token;
