-- 0007_create_driver_sessions.up.sql
--
-- Auth sessions for the driver app, mirroring 0002_create_sessions.up.sql.
-- Kept as its own table (rather than reusing sessions) because that table's
-- user_id FK targets users, not drivers.
--
-- REVIEW BEFORE PRODUCTION: token length/entropy, TTL, and a sweep of expired
-- rows (this schema leaves expiry cleanup to the application / a cron job).

CREATE TABLE IF NOT EXISTS driver_sessions (
    token      TEXT PRIMARY KEY,                                -- opaque, high-entropy bearer token
    driver_id  UUID        NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_sessions_driver_id ON driver_sessions (driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_sessions_expires_at ON driver_sessions (expires_at);
