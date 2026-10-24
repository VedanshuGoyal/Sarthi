-- 0010_booking_start_otp.up.sql
--
-- The code a driver must enter to start a ride. Issued when the ride is
-- accepted and shown only in the customer's app, so a trip can't start until
-- the driver is actually with the customer. Cleared if the driver hands the
-- ride back, and replaced after too many wrong attempts.
--
-- Plain text on purpose: it is a short-lived, per-ride handshake (like a cab
-- app's ride PIN), useless once the ride starts, and the customer's app must
-- be able to read it back.

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS start_otp TEXT;
