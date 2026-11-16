-- 0028_consent_and_erasure.down.sql
--
-- Drops the consent record and the erased marker. Erased rows stay
-- anonymised; only the timestamp saying so is lost.

ALTER TABLE users
    DROP COLUMN IF EXISTS consent_version,
    DROP COLUMN IF EXISTS consented_at,
    DROP COLUMN IF EXISTS erased_at;

ALTER TABLE drivers
    DROP COLUMN IF EXISTS consent_version,
    DROP COLUMN IF EXISTS consented_at,
    DROP COLUMN IF EXISTS erased_at;
