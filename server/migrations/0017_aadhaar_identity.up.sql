-- 0017_aadhaar_identity.up.sql
--
-- "One Aadhaar, one driver" was keyed on a fingerprint of the 12 digits the
-- driver typed, but DigiLocker only confirms the last four. A banned driver
-- could open a new account, type 8 other digits before their real last 4,
-- and pass DigiLocker with the same Aadhaar.
--
--   * aadhaar_identity_fingerprint — HMAC (server pepper) of what DigiLocker
--     verified: the Aadhaar's normalised name, date of birth and last 4.
--     Written on every successful DigiLocker verification and kept after,
--     so an identity stays claimed by the account that verified it.
--
-- Unique where set. Existing rows get NULL (the HMAC needs the server's
-- pepper, so there's no SQL backfill), so the index can't fail on them;
-- drivers verified before this are still matched, by the same values in
-- clear, when a new account verifies (see SaveAadhaarVerification).
-- Idempotent like every migration here (replayed on each local boot).

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS aadhaar_identity_fingerprint TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS drivers_aadhaar_identity_fingerprint
    ON drivers (aadhaar_identity_fingerprint)
    WHERE aadhaar_identity_fingerprint IS NOT NULL;
