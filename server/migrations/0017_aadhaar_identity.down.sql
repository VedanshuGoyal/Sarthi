-- 0017_aadhaar_identity.down.sql

DROP INDEX IF EXISTS drivers_aadhaar_identity_fingerprint;

ALTER TABLE drivers
    DROP COLUMN IF EXISTS aadhaar_identity_fingerprint;
