-- 0028_consent_and_erasure.up.sql
--
-- DPDP: record what each account agreed to, and mark accounts erased on
-- request (see service/erasure_service.go).
--
--   * consent_version — the Terms/Privacy version the app showed at sign-up,
--     e.g. '2026-11'. NULL for accounts made before this, and for old app
--     builds that don't send one.
--   * consented_at — when the server recorded that consent.
--   * erased_at — set when the account was anonymised. The row stays so
--     bookings and payments keep pointing at it (0018 made those RESTRICT).
--
-- Nullable columns with no default: a catalogue-only change, no table
-- rewrite, existing rows read NULL. Idempotent like every migration here.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS consent_version TEXT,
    ADD COLUMN IF NOT EXISTS consented_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS erased_at       TIMESTAMPTZ;

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS consent_version TEXT,
    ADD COLUMN IF NOT EXISTS consented_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS erased_at       TIMESTAMPTZ;
