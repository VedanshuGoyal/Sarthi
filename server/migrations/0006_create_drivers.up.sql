-- 0006_create_drivers.up.sql
--
-- Driver accounts created during phone-number registration, mirroring
-- 0001_create_users.up.sql. PostgreSQL is the source of truth for the
-- persistent fields (id, phone, name, vehicle); live state (status, location)
-- stays in memstore and is never written here.
--
-- REVIEW BEFORE PRODUCTION: column types, the unique constraint, and indexing
-- should be validated against real data volumes and access patterns.

CREATE TABLE IF NOT EXISTS drivers (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 TEXT        NOT NULL UNIQUE, -- full E.164, e.g. +919876543210
    name       TEXT        NOT NULL,
    vehicle    TEXT        NOT NULL DEFAULT '', -- filled in later, during vehicle onboarding
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
