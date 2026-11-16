-- 0019_kyc_cleared_selfie.up.sql
--
-- Customers recognise the person taking their car by the selfie, but
-- automatic clearance only checked that one had been uploaded. A verified
-- driver could upload anyone's photo, submit, and be cleared again within
-- seconds.
--
--   * kyc_cleared_selfie_sha256 — the hash of the selfie on file when the
--     driver was last cleared (automatically or by a reviewer). A driver
--     whose selfie differs from it is sent to a person instead of being
--     cleared automatically. NULL until the first clearance, which stays
--     automatic.
--
-- Backfill: drivers verified now get their current selfie's hash (an
-- upload reopens KYC, so a verified driver's selfie is the one cleared).
-- Re-running is a no-op. Idempotent like every migration here.

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS kyc_cleared_selfie_sha256 TEXT;

UPDATE drivers d
SET kyc_cleared_selfie_sha256 = doc.sha256
FROM driver_documents doc
WHERE doc.driver_id = d.id
  AND doc.kind = 'selfie'
  AND d.kyc_status = 'verified'
  AND d.kyc_cleared_selfie_sha256 IS NULL;
