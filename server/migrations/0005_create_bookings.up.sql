-- 0005_create_bookings.up.sql
--
-- Confirmed bookings submitted from the customer app. Until matchmaking and the
-- ride pipeline exist, this table is the source of truth for what a customer
-- asked for — low-frequency data (written once when a trip is confirmed),
-- deliberately NOT held in memstore, which is for hot real-time state.
--
-- Details is the schemaless per-trip-type payload the app sent (roundTrip,
-- oneWay and multiStop each carry a different shape), stored verbatim as JSONB
-- so the ride pipeline can be designed against real bookings without pinning a
-- column schema per trip type yet.

CREATE TABLE IF NOT EXISTS bookings (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trip_type  TEXT        NOT NULL, -- roundTrip | oneWay | multiStop
    details    JSONB       NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Serves the "my bookings, newest first" list read for a user.
CREATE INDEX IF NOT EXISTS bookings_user_created
    ON bookings (user_id, created_at DESC);
