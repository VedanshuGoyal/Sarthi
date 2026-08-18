-- 0008_create_driver_kyc.up.sql
--
-- Driver KYC: the six-step Document View in the driver app (vehicle type,
-- selfie + name, Aadhaar, driving licence, permissions, bank details).
--
-- Three pieces:
--   1. profile columns on `drivers` — the typed fields those steps collect
--   2. `driver_documents`  — one row per uploaded image; the bytes live in
--      object storage, this table holds only the key and its metadata
--   3. `driver_bank_accounts` — payout details, one per driver
--
-- Deliberately NOT in memstore: KYC is low-frequency (written once during
-- onboarding, read when an admin reviews) and must survive a restart.
--
-- On the two secret-handling patterns used below:
--
--   * Aadhaar numbers are never stored. UIDAI rules make holding the full
--     number a liability we have no reason to take on, so we keep the last 4
--     digits for display and an HMAC fingerprint for "is this Aadhaar already
--     registered to another driver?". The fingerprint is keyed with a server
--     pepper, so a leaked table cannot be brute-forced against the 10^12
--     Aadhaar space.
--   * Bank account numbers CANNOT be hashed — payouts need the real number
--     back — so they are encrypted at rest (AES-256-GCM, key held by the
--     server, never in the DB) with the last 4 digits kept in the clear for
--     the driver to recognise their own account.

-- --- 1. Driver profile fields collected during the Document View ---------

ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS date_of_birth          DATE,
    ADD COLUMN IF NOT EXISTS gender                 TEXT, -- male | female | other
    -- Which gearbox(es) the driver can drive, so matchmaking can respect a
    -- customer's preference. The driver app labels this step "Type of
    -- Vehicle", but the values it collects are transmissions.
    ADD COLUMN IF NOT EXISTS transmission           TEXT NOT NULL DEFAULT '', -- manual | automatic | both
    ADD COLUMN IF NOT EXISTS aadhaar_last4          TEXT,
    ADD COLUMN IF NOT EXISTS aadhaar_fingerprint    TEXT, -- HMAC-SHA256(pepper, digits)
    ADD COLUMN IF NOT EXISTS driving_license_number TEXT,
    -- Onboarding progress, owned by the server so the app can't self-certify:
    -- incomplete -> submitted -> verified | rejected.
    ADD COLUMN IF NOT EXISTS kyc_status             TEXT NOT NULL DEFAULT 'incomplete',
    ADD COLUMN IF NOT EXISTS kyc_submitted_at       TIMESTAMPTZ;

-- One Aadhaar, one driver. Partial so the many rows with no Aadhaar yet don't
-- collide on NULL.
CREATE UNIQUE INDEX IF NOT EXISTS drivers_aadhaar_fingerprint
    ON drivers (aadhaar_fingerprint)
    WHERE aadhaar_fingerprint IS NOT NULL;

-- --- 2. Uploaded KYC images ---------------------------------------------

CREATE TABLE IF NOT EXISTS driver_documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id     UUID        NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    -- selfie | aadhaar | driving_license. Free text rather than an enum type
    -- so adding a kind (an aadhaar back side, a vehicle RC) is a code change,
    -- not a migration; the service is the authority on what's accepted.
    kind          TEXT        NOT NULL,
    object_key    TEXT        NOT NULL, -- key in the blob store, e.g. drivers/<id>/selfie/<uuid>.jpg
    content_type  TEXT        NOT NULL, -- always image/jpeg today; the server re-encodes on upload
    byte_size     BIGINT      NOT NULL,
    sha256        TEXT        NOT NULL, -- of the stored (re-encoded) bytes, for integrity checks
    status        TEXT        NOT NULL DEFAULT 'pending', -- pending | verified | rejected
    reject_reason TEXT,
    uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at   TIMESTAMPTZ
);

-- A retake replaces the previous image rather than piling up: the service
-- upserts on this key and deletes the orphaned object from the blob store.
CREATE UNIQUE INDEX IF NOT EXISTS driver_documents_driver_kind
    ON driver_documents (driver_id, kind);

-- Serves the review queue ("what is still pending, oldest first").
CREATE INDEX IF NOT EXISTS driver_documents_status_uploaded
    ON driver_documents (status, uploaded_at);

-- --- 3. Payout details ---------------------------------------------------

CREATE TABLE IF NOT EXISTS driver_bank_accounts (
    driver_id                UUID PRIMARY KEY REFERENCES drivers(id) ON DELETE CASCADE,
    account_holder_name      TEXT        NOT NULL,
    account_number_encrypted BYTEA       NOT NULL, -- AES-256-GCM, nonce prefixed
    account_number_last4     TEXT        NOT NULL,
    ifsc_code                TEXT        NOT NULL, -- normalised uppercase, e.g. HDFC0001234
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
