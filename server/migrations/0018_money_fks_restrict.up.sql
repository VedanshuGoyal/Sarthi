-- 0018_money_fks_restrict.up.sql
--
-- Deleting a customer cascaded through their bookings and payment orders,
-- and deleting a driver nulled bookings.driver_id: either would erase paid
-- rides still owed to a driver from the books (DuePayouts). No code deletes
-- users, drivers or bookings; this stops a manual DELETE, or a future
-- account-deletion feature, from doing it silently. Accounts that must go
-- should be anonymised instead.
--
--   * bookings.user_id, bookings.driver_id, payment_orders.booking_id and
--     payment_orders.user_id become ON DELETE RESTRICT.
--
-- Each constraint is dropped and re-added under its default name, in one
-- transaction; re-adding checks existing rows, which the old constraints
-- already guaranteed. Re-running is a no-op in effect.
-- Idempotent like every migration here (replayed on each local boot).

BEGIN;

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_user_id_fkey,
    ADD CONSTRAINT bookings_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    DROP CONSTRAINT IF EXISTS bookings_driver_id_fkey,
    ADD CONSTRAINT bookings_driver_id_fkey
        FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE RESTRICT;

ALTER TABLE payment_orders
    DROP CONSTRAINT IF EXISTS payment_orders_booking_id_fkey,
    ADD CONSTRAINT payment_orders_booking_id_fkey
        FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE RESTRICT,
    DROP CONSTRAINT IF EXISTS payment_orders_user_id_fkey,
    ADD CONSTRAINT payment_orders_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- A constraint under another name would survive the drops above; refuse to
-- finish rather than leave a cascade in place.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE contype = 'f'
          AND confdeltype IN ('c', 'n', 'd') -- cascade, set null, set default
          AND conrelid IN ('bookings'::regclass, 'payment_orders'::regclass)
          AND confrelid IN ('users'::regclass, 'drivers'::regclass, 'bookings'::regclass)
    ) THEN
        RAISE EXCEPTION 'a cascading foreign key on bookings/payment_orders remains; check \d bookings';
    END IF;
END $$;

COMMIT;
