-- 0015_kyc_rejection_hold.up.sql
--
-- A reviewer's rejection must stick. kyc_status alone can't carry it: any
-- edit moves a driver to 'incomplete', and a later submit could then clear
-- them automatically.
--
--   * kyc_rejected_at — set when a reviewer rejects the driver (POST
--     /admin/kyc/{id}), cleared only when a reviewer verifies them. While it
--     is set, the driver's own submit can only reach 'submitted' (back in
--     front of a person), never 'verified'.
--
-- Backfill: drivers already rejected get the hold. Re-running is a no-op.
-- Idempotent like every migration here (replayed on each local boot).

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS kyc_rejected_at TIMESTAMPTZ;

UPDATE drivers
SET kyc_rejected_at = now()
WHERE kyc_status = 'rejected' AND kyc_rejected_at IS NULL;
