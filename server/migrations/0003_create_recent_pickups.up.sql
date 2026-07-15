-- 0003_create_recent_pickups.up.sql
--
-- Per-user pickup history: the handful of places a customer recently departed
-- from, so the apps can offer them without a maps-provider lookup. PostgreSQL is
-- the source of truth; each app mirrors it into on-device storage as an offline
-- cache. Low-frequency data (read when the pickup screen opens, written once per
-- booking) — deliberately NOT held in memstore, which is for hot real-time state.
--
-- REVIEW BEFORE PRODUCTION: retention policy. The service caps the list per user
-- (see MaxRecentPickups) and prunes on write, but consider also ageing out rows
-- older than N days as location history is privacy-sensitive.

CREATE TABLE IF NOT EXISTS recent_pickups (
    user_id   UUID             NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    place_id  TEXT             NOT NULL DEFAULT '',   -- map-provider id; '' for GPS-only points
    address   TEXT             NOT NULL,
    lat       DOUBLE PRECISION NOT NULL,
    lng       DOUBLE PRECISION NOT NULL,
    used_at   TIMESTAMPTZ      NOT NULL DEFAULT now(),

    -- Dedup identity: the place id when present, else the normalised address, so
    -- re-using a place upserts (bumps used_at) instead of adding a duplicate.
    dedup_key TEXT NOT NULL GENERATED ALWAYS AS
        (CASE WHEN place_id <> '' THEN place_id ELSE lower(address) END) STORED
);

CREATE UNIQUE INDEX IF NOT EXISTS recent_pickups_user_dedup
    ON recent_pickups (user_id, dedup_key);

-- Serves the "newest first" list read for a user.
CREATE INDEX IF NOT EXISTS recent_pickups_user_recent
    ON recent_pickups (user_id, used_at DESC);
