package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// ErrAccountNotFound is returned when no account of that kind has the id.
var ErrAccountNotFound = errors.New("account not found")

// ErasureRepository anonymises accounts on request (DPDP erasure). Rows that
// bookings and payments point at are overwritten, never deleted; everything
// else about the person is deleted.
type ErasureRepository struct {
	db DB
}

// NewErasureRepository wires the repository to a pool (or a test's tx).
func NewErasureRepository(db DB) *ErasureRepository {
	return &ErasureRepository{db: db}
}

// erasedCancelReason is what a booking cancelled by an erasure says.
const erasedCancelReason = "account deleted"

// EraseUser anonymises customer userID in one transaction. Under a lock on
// the account and its open bookings it reads what blocks erasure and passes
// it to allow; an error from allow aborts with nothing changed. Then:
//   - name, email, phone and date of birth are overwritten with placeholders
//     (phone and email are unique per id, so the number can sign up again);
//   - bookings no driver has taken are cancelled;
//   - sessions, push tokens, saved cars and recent pickups are deleted.
//
// Bookings and payment orders are kept. Re-running it on an erased account
// repeats the deletes and reports AlreadyErased.
func (r *ErasureRepository) EraseUser(
	ctx context.Context, userID string, at time.Time, allow func(domain.ErasureBlockers) error,
) (domain.ErasureResult, error) {
	var res domain.ErasureResult
	err := r.inTx(ctx, "erasing customer", func(tx pgx.Tx) error {
		erased, err := lockAccount(ctx, tx, `SELECT erased_at FROM users WHERE id = $1 FOR UPDATE`, userID)
		if err != nil {
			return err
		}
		res.AlreadyErased = erased
		// Lock the bookings that matter, so a driver can't accept a request
		// between this read and the cancel below.
		b, err := lockBlockers(ctx, tx, `
			SELECT CASE WHEN status IN ('completed', 'cancelled') THEN 'unpaid' ELSE status END
			FROM bookings
			WHERE user_id = $1
			  AND (status IN ('requested', 'accepted', 'arrived', 'in_progress')
			       OR (status = 'completed' AND paid_at IS NULL AND fare_paise > 0)
			       OR (status = 'cancelled' AND paid_at IS NULL AND cancellation_fee_paise IS NOT NULL))
			FOR UPDATE`, userID)
		if err != nil {
			return err
		}
		if err := allow(b); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE users
			SET name = $2,
			    email = 'deleted-' || id || '@deleted.invalid',
			    phone_e164 = 'deleted-' || id,
			    date_of_birth = DATE '1900-01-01',
			    erased_at = coalesce(erased_at, $3)
			WHERE id = $1`, userID, domain.ErasedName, at); err != nil {
			return fmt.Errorf("anonymising customer: %w", err)
		}
		tag, err := tx.Exec(ctx, `
			UPDATE bookings
			SET status = 'cancelled', cancelled_at = $2, cancelled_by = 'customer', cancel_reason = $3
			WHERE user_id = $1 AND status = 'requested'`, userID, at, erasedCancelReason)
		if err != nil {
			return fmt.Errorf("cancelling open bookings: %w", err)
		}
		res.CancelledRequests = int(tag.RowsAffected())
		return execAll(ctx, tx, userID,
			`DELETE FROM sessions WHERE user_id = $1`,
			`DELETE FROM push_tokens WHERE user_id = $1`,
			`DELETE FROM cars WHERE user_id = $1`,
			`DELETE FROM recent_pickups WHERE user_id = $1`,
		)
	})
	return res, err
}

// EraseDriver anonymises driver driverID in one transaction, like
// [ErasureRepository.EraseUser]: under a lock it checks allow, then
//   - overwrites name and phone, and clears every profile and verification
//     field (DigiLocker, licence, selfie hash, review notes);
//   - deletes the bank account, sessions, push tokens and declines;
//   - strips the licence number and Aadhaar digits from the KYC check log
//     (the rows stay for the cost audit until the retention sweep).
//
// The Aadhaar fingerprints are kept only for a driver a reviewer rejected,
// so a rejected identity can't come back on a fresh account. KYC images are
// returned in Documents, not deleted: the caller removes each from the bucket
// first, then its row ([ErasureRepository.DeleteDocument]), so a failed
// bucket delete leaves the row to retry from.
func (r *ErasureRepository) EraseDriver(
	ctx context.Context, driverID string, at time.Time, allow func(domain.ErasureBlockers) error,
) (domain.ErasureResult, error) {
	var res domain.ErasureResult
	err := r.inTx(ctx, "erasing driver", func(tx pgx.Tx) error {
		erased, err := lockAccount(ctx, tx, `SELECT erased_at FROM drivers WHERE id = $1 FOR UPDATE`, driverID)
		if err != nil {
			return err
		}
		res.AlreadyErased = erased
		// A paid ride whose share isn't paid out yet blocks too: the bank
		// account it would be paid to is deleted below.
		b, err := lockBlockers(ctx, tx, `
			SELECT CASE WHEN paid_at IS NOT NULL THEN 'payout'
			            WHEN status IN ('completed', 'cancelled') THEN 'unpaid'
			            ELSE status END
			FROM bookings
			WHERE driver_id = $1
			  AND (status IN ('accepted', 'arrived', 'in_progress')
			       OR (status = 'completed' AND paid_at IS NULL AND fare_paise > 0)
			       OR (status = 'cancelled' AND paid_at IS NULL AND cancellation_fee_paise IS NOT NULL)
			       OR (paid_at IS NOT NULL AND payout_id IS NULL AND paid_mode IS DISTINCT FROM 'cash'))
			FOR UPDATE`, driverID)
		if err != nil {
			return err
		}
		if err := allow(b); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE drivers
			SET name = $2,
			    phone_e164 = 'deleted-' || id,
			    vehicle = '',
			    date_of_birth = NULL,
			    gender = NULL,
			    transmission = '',
			    aadhaar_last4 = NULL,
			    aadhaar_fingerprint = CASE WHEN kyc_rejected_at IS NOT NULL THEN aadhaar_fingerprint END,
			    aadhaar_identity_fingerprint =
			        CASE WHEN kyc_rejected_at IS NOT NULL THEN aadhaar_identity_fingerprint END,
			    driving_license_number = NULL,
			    kyc_status = 'incomplete',
			    kyc_submitted_at = NULL,
			    aadhaar_verified_at = NULL,
			    digilocker_client_id = NULL,
			    license_verified_at = NULL,
			    license_name = NULL,
			    license_valid_until = NULL,
			    license_vehicle_classes = NULL,
			    kyc_review_note = NULL,
			    kyc_cleared_selfie_sha256 = NULL,
			    erased_at = coalesce(erased_at, $3)
			WHERE id = $1`, driverID, domain.ErasedName, at); err != nil {
			return fmt.Errorf("anonymising driver: %w", err)
		}
		if err := execAll(ctx, tx, driverID,
			`DELETE FROM driver_bank_accounts WHERE driver_id = $1`,
			`DELETE FROM driver_sessions WHERE driver_id = $1`,
			`DELETE FROM push_tokens WHERE driver_id = $1`,
			`DELETE FROM booking_declines WHERE driver_id = $1`,
			`UPDATE driver_kyc_checks SET provider_ref = NULL, detail = NULL WHERE driver_id = $1`,
		); err != nil {
			return err
		}
		res.Documents, err = queryDocuments(ctx, tx, `
			SELECT id::text, driver_id::text, object_key FROM driver_documents
			WHERE driver_id = $1 ORDER BY uploaded_at`, driverID)
		if err != nil {
			return fmt.Errorf("listing documents: %w", err)
		}
		return nil
	})
	return res, err
}

// DeleteDocument removes one KYC image row once its object is gone from the
// bucket. A row already gone is not an error.
func (r *ErasureRepository) DeleteDocument(ctx context.Context, documentID string) error {
	if _, err := r.db.Exec(ctx, `DELETE FROM driver_documents WHERE id = $1`, documentID); err != nil {
		return fmt.Errorf("deleting document: %w", err)
	}
	return nil
}

// ErasedDriverDocuments lists up to limit KYC images still held for erased
// drivers: bucket deletes that failed during an erasure, for the retention
// sweep to finish.
func (r *ErasureRepository) ErasedDriverDocuments(ctx context.Context, limit int) ([]domain.StoredDocument, error) {
	docs, err := queryDocuments(ctx, r.db, `
		SELECT doc.id::text, doc.driver_id::text, doc.object_key
		FROM driver_documents doc
		JOIN drivers d ON d.id = doc.driver_id
		WHERE d.erased_at IS NOT NULL
		ORDER BY doc.uploaded_at
		LIMIT $1`, limit)
	if err != nil {
		return nil, fmt.Errorf("listing erased drivers' documents: %w", err)
	}
	return docs, nil
}

// inTx runs fn in a transaction, committing if it returns nil. fn's error
// comes back as is, so the caller can branch on allow's and
// [ErrAccountNotFound].
func (r *ErasureRepository) inTx(ctx context.Context, doing string, fn func(pgx.Tx) error) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("%s: %w", doing, err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("%s: %w", doing, err)
	}
	return nil
}

// lockAccount locks one account row and reports whether it was erased
// before; [ErrAccountNotFound] if there is none.
func lockAccount(ctx context.Context, tx pgx.Tx, q, id string) (bool, error) {
	var erasedAt *time.Time
	err := tx.QueryRow(ctx, q, id).Scan(&erasedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrAccountNotFound
	}
	if err != nil {
		return false, fmt.Errorf("locking account: %w", err)
	}
	return erasedAt != nil, nil
}

// lockBlockers runs q, which locks each booking of the account that could
// block erasure and returns what it is — 'unpaid' (completed, not paid),
// 'payout' (paid, the driver's share not paid out) or else its status — and
// counts them. An open request blocks nothing: erasure cancels it.
func lockBlockers(ctx context.Context, tx pgx.Tx, q, id string) (domain.ErasureBlockers, error) {
	var b domain.ErasureBlockers
	rows, err := tx.Query(ctx, q, id)
	if err != nil {
		return b, fmt.Errorf("checking rides: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var kind string
		if err := rows.Scan(&kind); err != nil {
			return b, fmt.Errorf("checking rides: %w", err)
		}
		switch kind {
		case "unpaid":
			b.UnpaidRides++
		case "payout":
			b.AwaitingPayout++
		case string(domain.RideStatusRequested):
		default:
			b.ActiveRides++
		}
	}
	if err := rows.Err(); err != nil {
		return b, fmt.Errorf("checking rides: %w", err)
	}
	return b, nil
}

// execAll runs each statement with id as $1.
func execAll(ctx context.Context, tx pgx.Tx, id string, statements ...string) error {
	for _, q := range statements {
		if _, err := tx.Exec(ctx, q, id); err != nil {
			return fmt.Errorf("erasing account: %w", err)
		}
	}
	return nil
}

// queryDocuments scans (id, driver_id, object_key) rows.
func queryDocuments(ctx context.Context, db interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}, q string, args ...any) ([]domain.StoredDocument, error) {
	rows, err := db.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	docs := []domain.StoredDocument{}
	for rows.Next() {
		var d domain.StoredDocument
		if err := rows.Scan(&d.ID, &d.DriverID, &d.ObjectKey); err != nil {
			return nil, err
		}
		docs = append(docs, d)
	}
	return docs, rows.Err()
}
