-- 0026_admin_actions.up.sql
--
-- An audit row for every back-office change: who (the name the operator
-- gave the admin page; the token itself is shared), what, on which record,
-- the particulars, and when. Written for booking assign / cancel / settle,
-- KYC decisions and payouts (HUMAN REVIEW REQUIRED: payments/KYC).
--
--   actor   — the operator's name, or 'admin' when they gave none
--   action  — 'booking.assign', 'booking.cancel', 'booking.settle',
--             'kyc.decide', 'payout.record'
--   target  — the booking, driver or payout id acted on
--   details — JSONB: the reason, mode, amount, the caller's IP …
--
-- New table only; nothing existing changes. Idempotent like every
-- migration here (replayed on each local boot).

CREATE TABLE IF NOT EXISTS admin_actions (
    id      BIGSERIAL   PRIMARY KEY,
    actor   TEXT        NOT NULL,
    action  TEXT        NOT NULL,
    target  TEXT        NOT NULL,
    details JSONB       NOT NULL DEFAULT '{}'::jsonb,
    at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Serves the admin page's recent-actions list, and one record's history.
CREATE INDEX IF NOT EXISTS admin_actions_at ON admin_actions (at DESC);
CREATE INDEX IF NOT EXISTS admin_actions_target_at ON admin_actions (target, at DESC);
