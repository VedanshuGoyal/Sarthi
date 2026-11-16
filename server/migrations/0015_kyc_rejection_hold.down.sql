-- 0015_kyc_rejection_hold.down.sql

ALTER TABLE drivers
    DROP COLUMN IF EXISTS kyc_rejected_at;
