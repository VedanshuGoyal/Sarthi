-- 0014_driver_kyc_checks.up.sql
--
-- Driver KYC is now checked against the source, through Surepass:
--
--   * Aadhaar through DigiLocker — the driver signs in to DigiLocker and we
--     read back the Aadhaar's name, date of birth, gender and last 4 digits.
--     The name/DOB/gender overwrite what the driver typed and are then
--     locked; aadhaar_verified_at marks it done. digilocker_client_id is the
--     session the driver has open (cleared once it has been read).
--   * Driving licence — looked up by number and date of birth; we keep the
--     name, expiry and vehicle classes it carries.
--   * Bank account — a penny drop; we keep the name the bank holds for it.
--
-- kyc_review_note says why a submission went to a person instead of being
-- cleared automatically, or why a reviewer rejected it.
--
-- driver_kyc_checks logs every call to the provider: an audit trail, and the
-- count behind the per-driver daily limit (each call costs money).
--
-- Idempotent like every migration here (replayed on each local boot).

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS aadhaar_verified_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS digilocker_client_id    TEXT,
    ADD COLUMN IF NOT EXISTS license_verified_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS license_name            TEXT,
    ADD COLUMN IF NOT EXISTS license_valid_until     DATE,
    ADD COLUMN IF NOT EXISTS license_vehicle_classes TEXT[],
    ADD COLUMN IF NOT EXISTS kyc_review_note         TEXT;

ALTER TABLE driver_bank_accounts
    ADD COLUMN IF NOT EXISTS verified_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verified_name TEXT;

CREATE TABLE IF NOT EXISTS driver_kyc_checks (
    id           BIGSERIAL PRIMARY KEY,
    driver_id    UUID        NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    kind         TEXT        NOT NULL, -- digilocker | driving_license | bank_account
    provider_ref TEXT,                 -- Surepass client_id, when it gave one
    outcome      TEXT        NOT NULL, -- started | verified | pending | not_found | rejected | failed | error
    detail       TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS driver_kyc_checks_driver_kind_created
    ON driver_kyc_checks (driver_id, kind, created_at);

-- The review queue: drivers waiting on a person.
CREATE INDEX IF NOT EXISTS drivers_kyc_status
    ON drivers (kyc_status, kyc_submitted_at);
