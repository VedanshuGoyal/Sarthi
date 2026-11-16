-- 0020_hash_session_tokens.up.sql
--
-- Sessions now store SHA-256(token), hex-encoded, instead of the bearer token
-- itself (see service.tokenKey), so a dump or backup of these tables holds no
-- working credentials. This converts the tokens issued before the change.
--
-- Raw tokens are 43-char base64url; hashed ones are 64 lowercase hex chars,
-- so already-converted rows are skipped and the migration is idempotent.
-- Apply it together with the server build that hashes tokens: in between,
-- signed-in users are asked to sign in again.

UPDATE sessions
SET token = encode(sha256(convert_to(token, 'UTF8')), 'hex')
WHERE token !~ '^[0-9a-f]{64}$';

UPDATE driver_sessions
SET token = encode(sha256(convert_to(token, 'UTF8')), 'hex')
WHERE token !~ '^[0-9a-f]{64}$';
