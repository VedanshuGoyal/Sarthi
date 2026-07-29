-- 0004_create_cars.up.sql
--
-- Each customer's saved cars. Sarthi drivers drive the customer's own car, so
-- instead of re-picking a car type and gearbox on every booking the customer
-- registers a car once (registration number, type, transmission) and picks it
-- from a dropdown. PostgreSQL is the source of truth; low-frequency data (read
-- when a booking step opens, written when a car is added) — deliberately NOT
-- held in memstore, which is for hot real-time state.
--
-- The service stores registration normalised (uppercase, separators stripped,
-- e.g. "ka 01 ab 1234" -> "KA01AB1234"), so a plain per-user unique index is
-- enough to stop duplicates.

CREATE TABLE IF NOT EXISTS cars (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    registration TEXT        NOT NULL, -- normalised plate, e.g. KA01AB1234
    car_type     TEXT        NOT NULL, -- hatchback | sedan | suv | luxury
    transmission TEXT        NOT NULL, -- automatic | manual
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS cars_user_registration
    ON cars (user_id, registration);

-- Serves the "newest first" list read for a user.
CREATE INDEX IF NOT EXISTS cars_user_created
    ON cars (user_id, created_at DESC);
