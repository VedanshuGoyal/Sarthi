-- 0011_push_tokens.up.sql
--
-- Firebase Cloud Messaging registration tokens, one row per app install, so
-- the server can push "new ride request" to drivers and "driver assigned" to
-- customers. Exactly one of user_id / driver_id is set: the customer and
-- driver apps are separate Firebase apps with tokens of their own.
--
-- The token is the key: when another account signs in on the same phone the
-- row moves to them. Rows are dropped when the app signs out, or when FCM
-- reports the token is no longer registered (app uninstalled).

CREATE TABLE IF NOT EXISTS push_tokens (
    token      TEXT PRIMARY KEY,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    driver_id  UUID REFERENCES drivers(id) ON DELETE CASCADE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT push_tokens_one_owner CHECK ((user_id IS NULL) <> (driver_id IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON push_tokens (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_push_tokens_driver_id ON push_tokens (driver_id) WHERE driver_id IS NOT NULL;
