-- 0029_retention_indexes.up.sql
--
-- Indexes for the daily retention sweep (service/retention_service.go):
--
--   * driver_kyc_checks_created — rows older than 180 days are deleted; the
--     existing index leads with driver_id, so it can't serve that.
--   * drivers_erased — finds erased drivers whose KYC images still need
--     deleting from the bucket (a failed delete is retried by the sweep).
--     Partial: only erased rows are indexed.
--
-- (sessions and driver_sessions already index expires_at, 0002 / 0007.)
-- Both tables are tiny today, so a plain CREATE INDEX holds its lock for
-- milliseconds. Idempotent like every migration here.

CREATE INDEX IF NOT EXISTS driver_kyc_checks_created
    ON driver_kyc_checks (created_at);

CREATE INDEX IF NOT EXISTS drivers_erased
    ON drivers (erased_at)
    WHERE erased_at IS NOT NULL;
