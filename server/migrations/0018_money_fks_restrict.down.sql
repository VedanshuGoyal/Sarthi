-- 0018_money_fks_restrict.down.sql — back to the 0005 / 0009 / 0013 rules.

BEGIN;

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_user_id_fkey,
    ADD CONSTRAINT bookings_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    DROP CONSTRAINT IF EXISTS bookings_driver_id_fkey,
    ADD CONSTRAINT bookings_driver_id_fkey
        FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE SET NULL;

ALTER TABLE payment_orders
    DROP CONSTRAINT IF EXISTS payment_orders_booking_id_fkey,
    ADD CONSTRAINT payment_orders_booking_id_fkey
        FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE,
    DROP CONSTRAINT IF EXISTS payment_orders_user_id_fkey,
    ADD CONSTRAINT payment_orders_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

COMMIT;
