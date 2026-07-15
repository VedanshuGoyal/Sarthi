-- 0002_create_sessions.up.sql
--
-- Auth sessions: opaque bearer tokens issued on login/registration. PostgreSQL
-- is the source of truth so sessions survive a restart; the server also caches
-- live sessions in memstore for O(1) validation without a per-request DB hit,
-- rebuilding that cache from this table on boot.
--
-- REVIEW BEFORE PRODUCTION: token length/entropy, TTL, and a sweep of expired
-- rows (this schema leaves expiry cleanup to the application / a cron job).

CREATE TABLE IF NOT EXISTS sessions (
    token      TEXT PRIMARY KEY,                              -- opaque, high-entropy bearer token
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at);
