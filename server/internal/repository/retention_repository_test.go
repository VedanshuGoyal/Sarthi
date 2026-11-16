package repository

import (
	"testing"
	"time"
)

func TestRetentionRepository_DeletesOnlyPastTheCutoff_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewRetentionRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	now := time.Now()

	for _, q := range []string{
		`INSERT INTO sessions (token, user_id, expires_at) VALUES ('ret-old-' || $1::text, $1::uuid, $2::timestamptz - interval '8 days')`,
		`INSERT INTO sessions (token, user_id, expires_at) VALUES ('ret-new-' || $1::text, $1::uuid, $2::timestamptz - interval '6 days')`,
	} {
		if _, err := tx.Exec(ctx, q, user, now); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	for _, q := range []string{
		`INSERT INTO driver_sessions (token, driver_id, expires_at) VALUES ('ret-old-' || $1::text, $1::uuid, $2::timestamptz - interval '8 days')`,
		`INSERT INTO driver_sessions (token, driver_id, expires_at) VALUES ('ret-new-' || $1::text, $1::uuid, $2::timestamptz + interval '1 day')`,
		`INSERT INTO driver_kyc_checks (driver_id, kind, outcome, created_at) VALUES ($1::uuid, 'bank_account', 'verified', $2::timestamptz - interval '181 days')`,
		`INSERT INTO driver_kyc_checks (driver_id, kind, outcome, created_at) VALUES ($1::uuid, 'bank_account', 'verified', $2::timestamptz - interval '179 days')`,
	} {
		if _, err := tx.Exec(ctx, q, driver, now); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}

	if _, err := repo.DeleteSessionsExpiredBefore(ctx, now.AddDate(0, 0, -7)); err != nil {
		t.Fatalf("DeleteSessionsExpiredBefore: %v", err)
	}
	if _, err := repo.DeleteKYCChecksBefore(ctx, now.AddDate(0, 0, -180)); err != nil {
		t.Fatalf("DeleteKYCChecksBefore: %v", err)
	}

	if n := count(t, ctx, tx, `SELECT count(*) FROM sessions WHERE user_id = $1 AND token LIKE 'ret-old-%'`, user); n != 0 {
		t.Error("a customer session expired 8 days ago survived")
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM sessions WHERE user_id = $1 AND token LIKE 'ret-new-%'`, user); n != 1 {
		t.Error("a customer session expired 6 days ago was deleted")
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM driver_sessions WHERE driver_id = $1`, driver); n != 1 {
		t.Errorf("driver sessions left: %d, want only the live one", n)
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM driver_kyc_checks WHERE driver_id = $1`, driver); n != 1 {
		t.Errorf("KYC checks left: %d, want only the 179-day-old one", n)
	}
}
