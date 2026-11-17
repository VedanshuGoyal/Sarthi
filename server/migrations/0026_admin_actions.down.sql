-- 0026_admin_actions.down.sql
--
-- Drops the back-office audit trail. Its rows are the only record of who
-- did what from the admin page; dump the table first.

DROP TABLE IF EXISTS admin_actions;
