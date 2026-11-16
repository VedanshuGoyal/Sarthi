-- 0019_kyc_cleared_selfie.down.sql

ALTER TABLE drivers
    DROP COLUMN IF EXISTS kyc_cleared_selfie_sha256;
