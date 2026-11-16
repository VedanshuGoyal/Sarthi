package repository

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// newTestDriver inserts a driver through db and returns its id.
func newTestDriver(t *testing.T, ctx context.Context, db DB) string {
	t.Helper()
	var id string
	phone := fmt.Sprintf("+9170%08d", time.Now().UnixNano()%100_000_000)
	if err := db.QueryRow(ctx,
		`INSERT INTO drivers (phone_e164, name) VALUES ($1, 'Test Driver') RETURNING id`, phone,
	).Scan(&id); err != nil {
		t.Fatalf("inserting driver: %v", err)
	}
	return id
}

func kycStatus(t *testing.T, ctx context.Context, db DB, driverID string) (domain.KYCStatus, *time.Time) {
	t.Helper()
	var (
		status   domain.KYCStatus
		rejected *time.Time
	)
	if err := db.QueryRow(ctx, `SELECT kyc_status, kyc_rejected_at FROM drivers WHERE id = $1`, driverID).
		Scan(&status, &rejected); err != nil {
		t.Fatalf("reading status: %v", err)
	}
	return status, rejected
}

func rollbackTx(t *testing.T) (context.Context, pgx.Tx) {
	t.Helper()
	ctx := context.Background()
	tx, err := testDB(t).Begin(ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	t.Cleanup(func() { _ = tx.Rollback(ctx) })
	return ctx, tx
}

func TestDriverKYCRepository_RejectionSticks_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewDriverKYCRepository(tx)
	id := newTestDriver(t, ctx, tx)

	if err := repo.ReviewKYC(ctx, id, domain.KYCRejected, "Blurry selfie", ""); err != nil {
		t.Fatalf("ReviewKYC(rejected): %v", err)
	}
	if status, rejected := kycStatus(t, ctx, tx, id); status != domain.KYCRejected || rejected == nil {
		t.Fatalf("after reject: status %q, hold %v", status, rejected)
	}

	// Every edit path leaves a rejected driver rejected.
	if err := repo.SetKYCStatus(ctx, id, domain.KYCIncomplete, false); err != nil {
		t.Fatalf("SetKYCStatus: %v", err)
	}
	if err := repo.SaveAadhaarVerification(ctx, id, domain.AadhaarRecord{
		Name: "Test Driver", DateOfBirth: time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("SaveAadhaarVerification: %v", err)
	}
	if err := repo.SaveLicenseVerification(ctx, id, domain.LicenseRecord{Number: "DL0420110012345"}); err != nil {
		t.Fatalf("SaveLicenseVerification: %v", err)
	}
	if status, _ := kycStatus(t, ctx, tx, id); status != domain.KYCRejected {
		t.Fatalf("after edits: status %q, want rejected", status)
	}

	// The driver's submission is written as decided, and the hold survives it.
	err := repo.DecideSubmission(ctx, id, func(k domain.DriverKYC) (domain.KYCStatus, string, error) {
		if k.Profile.KYCRejectedAt == nil {
			t.Error("decide didn't see the hold")
		}
		return domain.KYCSubmitted, k.Profile.KYCReviewNote, nil
	})
	if err != nil {
		t.Fatalf("DecideSubmission: %v", err)
	}
	if status, rejected := kycStatus(t, ctx, tx, id); status != domain.KYCSubmitted || rejected == nil {
		t.Fatalf("after resubmit: status %q, hold %v", status, rejected)
	}
	// Out of the rejected state, an edit reopens them as usual.
	if err := repo.SetKYCStatus(ctx, id, domain.KYCIncomplete, false); err != nil {
		t.Fatalf("SetKYCStatus: %v", err)
	}
	if status, rejected := kycStatus(t, ctx, tx, id); status != domain.KYCIncomplete || rejected == nil {
		t.Fatalf("after an edit while waiting: status %q, hold %v", status, rejected)
	}

	// A reviewer's approval on a stale view is refused; on the current one it
	// lands and lifts the hold.
	if err := repo.ReviewKYC(ctx, id, domain.KYCVerified, "", domain.KYCSubmitted); !errors.Is(err, ErrKYCChanged) {
		t.Fatalf("stale ReviewKYC: err = %v, want ErrKYCChanged", err)
	}
	if err := repo.ReviewKYC(ctx, id, domain.KYCVerified, "", domain.KYCIncomplete); err != nil {
		t.Fatalf("ReviewKYC(verified): %v", err)
	}
	if status, rejected := kycStatus(t, ctx, tx, id); status != domain.KYCVerified || rejected != nil {
		t.Fatalf("after approval: status %q, hold %v", status, rejected)
	}

	missing := "00000000-0000-0000-0000-000000000000"
	if err := repo.ReviewKYC(ctx, missing, domain.KYCVerified, "", domain.KYCSubmitted); !errors.Is(err, ErrDriverNotFound) {
		t.Errorf("unknown driver: err = %v, want ErrDriverNotFound", err)
	}
}

// An edit that arrives while a submission is being decided waits for it, and
// then reopens the driver: it can't be overwritten by a decision made on the
// state from before it.
func TestDriverKYCRepository_DecideSubmissionLocksTheDriver_Integration(t *testing.T) {
	ctx := context.Background()
	pool := testDB(t)
	repo := NewDriverKYCRepository(pool)
	id := newTestDriver(t, ctx, pool)
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM drivers WHERE id = $1`, id) })

	deciding, release := make(chan struct{}), make(chan struct{})
	submitted := make(chan error, 1)
	go func() {
		submitted <- repo.DecideSubmission(ctx, id, func(domain.DriverKYC) (domain.KYCStatus, string, error) {
			close(deciding)
			<-release
			return domain.KYCVerified, "", nil
		})
	}()
	<-deciding

	edited := make(chan error, 1)
	go func() { edited <- repo.SetKYCStatus(ctx, id, domain.KYCIncomplete, false) }()
	select {
	case err := <-edited:
		t.Fatalf("the edit didn't wait for the submission (err %v)", err)
	case <-time.After(200 * time.Millisecond):
	}
	close(release)
	if err := <-submitted; err != nil {
		t.Fatalf("DecideSubmission: %v", err)
	}
	if err := <-edited; err != nil {
		t.Fatalf("SetKYCStatus: %v", err)
	}
	if status, _ := kycStatus(t, ctx, pool, id); status != domain.KYCIncomplete {
		t.Errorf("status = %q, want incomplete: the later edit wins", status)
	}
}
