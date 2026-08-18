-- 0008_create_driver_kyc.down.sql
DROP TABLE IF EXISTS driver_bank_accounts;
DROP TABLE IF EXISTS driver_documents;

DROP INDEX IF EXISTS drivers_aadhaar_fingerprint;

ALTER TABLE drivers
    DROP COLUMN IF EXISTS date_of_birth,
    DROP COLUMN IF EXISTS gender,
    DROP COLUMN IF EXISTS transmission,
    DROP COLUMN IF EXISTS aadhaar_last4,
    DROP COLUMN IF EXISTS aadhaar_fingerprint,
    DROP COLUMN IF EXISTS driving_license_number,
    DROP COLUMN IF EXISTS kyc_status,
    DROP COLUMN IF EXISTS kyc_submitted_at;
