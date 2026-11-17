-- 0031_payment_order_items.down.sql
--
-- Drops the record of which bookings each checkout paid. Bookings keep
-- paid_at and payment_order_id, so nothing owed or paid is lost; an older
-- server reads only an order's own booking.

DROP INDEX IF EXISTS payment_order_items_booking;
DROP TABLE IF EXISTS payment_order_items;
