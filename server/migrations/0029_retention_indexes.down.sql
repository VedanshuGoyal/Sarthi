-- 0029_retention_indexes.down.sql

DROP INDEX IF EXISTS driver_kyc_checks_created;
DROP INDEX IF EXISTS drivers_erased;
