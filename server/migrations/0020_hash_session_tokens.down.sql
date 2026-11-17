-- 0020_hash_session_tokens.down.sql
--
-- Irreversible: a hash cannot be turned back into its token. Rolling back to a
-- server that compares raw tokens just signs everyone out; to make that clean,
-- drop the now-useless rows.

DELETE FROM sessions WHERE token ~ '^[0-9a-f]{64}$';
DELETE FROM driver_sessions WHERE token ~ '^[0-9a-f]{64}$';
