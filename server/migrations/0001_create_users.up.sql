-- 0001_create_users.up.sql
--
-- Customer accounts created during phone-number registration. PostgreSQL is the
-- source of truth for accounts (memstore holds only hot, rebuildable state).
--
-- REVIEW BEFORE PRODUCTION: column types, the unique constraint, and indexing
-- should be validated against real data volumes and access patterns.

CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164    TEXT        NOT NULL UNIQUE, -- full E.164, e.g. +919876543210
    name          TEXT        NOT NULL,
    email         TEXT        NOT NULL,
    date_of_birth DATE        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
