-- 0014_driver_kyc_checks.down.sql

DROP INDEX IF EXISTS drivers_kyc_status;
DROP TABLE IF EXISTS driver_kyc_checks;

ALTER TABLE driver_bank_accounts
    DROP COLUMN IF EXISTS verified_name,
    DROP COLUMN IF EXISTS verified_at;

ALTER TABLE drivers
    DROP COLUMN IF EXISTS kyc_review_note,
    DROP COLUMN IF EXISTS license_vehicle_classes,
    DROP COLUMN IF EXISTS license_valid_until,
    DROP COLUMN IF EXISTS license_name,
    DROP COLUMN IF EXISTS license_verified_at,
    DROP COLUMN IF EXISTS digilocker_client_id,
    DROP COLUMN IF EXISTS aadhaar_verified_at;
