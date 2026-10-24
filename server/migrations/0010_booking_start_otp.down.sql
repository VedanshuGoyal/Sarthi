-- 0010_booking_start_otp.down.sql
ALTER TABLE bookings DROP COLUMN IF EXISTS start_otp;
