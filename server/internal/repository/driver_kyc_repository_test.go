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
		Name: "Test Driver", DateOfBirth: time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC), Last4: "0001",
	}, "fp-"+id); err != nil {
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

// inSavepoint runs fn on a savepoint of tx, rolling it back if fn fails, so
// an expected constraint violation doesn't abort the test's transaction.
func inSavepoint(t *testing.T, ctx context.Context, tx pgx.Tx, fn func(DB) error) error {
	t.Helper()
	sp, err := tx.Begin(ctx)
	if err != nil {
		t.Fatalf("savepoint: %v", err)
	}
	if err := fn(sp); err != nil {
		_ = sp.Rollback(ctx)
		return err
	}
	if err := sp.Commit(ctx); err != nil {
		t.Fatalf("releasing savepoint: %v", err)
	}
	return nil
}

func TestDriverKYCRepository_OneAadhaarIdentityOneDriver_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	dob := time.Date(1991, 5, 6, 0, 0, 0, 0, time.UTC)
	tag := fmt.Sprint(time.Now().UnixNano())
	asha := domain.AadhaarRecord{Name: "Asha Kumari", DateOfBirth: dob, Last4: "9012"}
	save := func(driverID string, rec domain.AadhaarRecord, fp string) error {
		return inSavepoint(t, ctx, tx, func(db DB) error {
			return NewDriverKYCRepository(db).SaveAadhaarVerification(ctx, driverID, rec, fp)
		})
	}

	first, second := newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx)
	if err := save(first, asha, "asha-"+tag); err != nil {
		t.Fatalf("first driver: %v", err)
	}
	if err := save(first, asha, "asha-"+tag); err != nil {
		t.Fatalf("first driver verifying again: %v", err)
	}
	if err := save(second, asha, "asha-"+tag); !errors.Is(err, ErrAadhaarTaken) {
		t.Fatalf("second driver, same identity: err = %v, want ErrAadhaarTaken", err)
	}

	// A driver verified before fingerprints were kept is matched by the
	// identity in clear, whatever the case and spacing of the name.
	legacy := newTestDriver(t, ctx, tx)
	if _, err := tx.Exec(ctx, `
		UPDATE drivers SET name = ' RAVI   kumar', date_of_birth = $2, aadhaar_last4 = '4321',
		       aadhaar_verified_at = now()
		WHERE id = $1`, legacy, dob); err != nil {
		t.Fatalf("legacy driver: %v", err)
	}
	ravi := domain.AadhaarRecord{Name: "Ravi Kumar", DateOfBirth: dob, Last4: "4321"}
	if err := save(second, ravi, "ravi-"+tag); !errors.Is(err, ErrAadhaarTaken) {
		t.Fatalf("matching a legacy driver: err = %v, want ErrAadhaarTaken", err)
	}
	ravi.Last4 = "4322"
	if err := save(second, ravi, "ravi2-"+tag); err != nil {
		t.Fatalf("a different identity: %v", err)
	}
}

func TestDriverKYCRepository_ClearingRecordsTheSelfie_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewDriverKYCRepository(tx)
	id := newTestDriver(t, ctx, tx)
	selfie := func(sha string) {
		t.Helper()
		if _, _, err := repo.UpsertDocument(ctx, id, UpsertDocumentParams{
			Kind: domain.DocumentSelfie, ObjectKey: "k-" + sha, ContentType: "image/jpeg", ByteSize: 1, SHA256: sha,
		}); err != nil {
			t.Fatalf("UpsertDocument: %v", err)
		}
	}
	cleared := func() string {
		t.Helper()
		p, err := repo.FindProfile(ctx, id)
		if err != nil {
			t.Fatalf("FindProfile: %v", err)
		}
		return p.ClearedSelfieSHA256
	}
	verify := func(domain.DriverKYC) (domain.KYCStatus, string, error) { return domain.KYCVerified, "", nil }
	review := func(domain.DriverKYC) (domain.KYCStatus, string, error) { return domain.KYCSubmitted, "look", nil }

	selfie("aaa")
	if err := repo.DecideSubmission(ctx, id, review); err != nil {
		t.Fatal(err)
	}
	if got := cleared(); got != "" {
		t.Fatalf("sent to review, yet cleared selfie = %q", got)
	}
	if err := repo.DecideSubmission(ctx, id, verify); err != nil {
		t.Fatal(err)
	}
	if got := cleared(); got != "aaa" {
		t.Fatalf("after auto-clearance cleared selfie = %q, want aaa", got)
	}
	selfie("bbb")
	if err := repo.ReviewKYC(ctx, id, domain.KYCVerified, "", ""); err != nil {
		t.Fatal(err)
	}
	if got := cleared(); got != "bbb" {
		t.Errorf("after a reviewer's approval cleared selfie = %q, want bbb", got)
	}
}

func TestDriverKYCRepository_CountAllChecks_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewDriverKYCRepository(tx)
	since := time.Now().Add(-time.Minute)
	before, err := repo.CountAllChecks(ctx, since)
	if err != nil {
		t.Fatalf("CountAllChecks: %v", err)
	}
	a, b := newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx)
	for _, c := range []struct {
		driver  string
		kind    domain.KYCCheckKind
		outcome domain.KYCCheckOutcome
	}{
		{a, domain.CheckDrivingLicense, domain.CheckNotFound}, // counts
		{a, domain.CheckBankAccount, domain.CheckVerified},    // counts
		{b, domain.CheckDigiLocker, domain.CheckStarted},      // counts
		{b, domain.CheckDigiLocker, domain.CheckVerified},     // the same session's result
		{b, domain.CheckBankAccount, domain.CheckError},       // the provider didn't answer
	} {
		if err := repo.RecordCheck(ctx, c.driver, c.kind, "", c.outcome, ""); err != nil {
			t.Fatalf("RecordCheck: %v", err)
		}
	}
	if n, err := repo.CountAllChecks(ctx, since); err != nil || n-before != 3 {
		t.Errorf("CountAllChecks = %d (+%d), %v; want +3", n, n-before, err)
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
