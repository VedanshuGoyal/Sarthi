package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// ErrDocumentNotFound is returned when a driver has no document of a kind.
var ErrDocumentNotFound = errors.New("document not found")

// ErrBankAccountNotFound is returned when a driver has no payout details yet.
var ErrBankAccountNotFound = errors.New("bank account not found")

// ErrAadhaarTaken is returned when an Aadhaar number is already registered to
// a different driver, detected by the unique index on the fingerprint.
var ErrAadhaarTaken = errors.New("this Aadhaar number is already registered")

// aadhaarFingerprintIndex is the unique index from 0008_create_driver_kyc that
// enforces one Aadhaar per driver. Matched by name so an unrelated future
// constraint on `drivers` isn't misreported as a duplicate Aadhaar.
const aadhaarFingerprintIndex = "drivers_aadhaar_fingerprint"

// documentColumns is the shared SELECT list, in DriverDocument field order.
const documentColumns = `id, kind, object_key, content_type, byte_size, sha256,
	status, coalesce(reject_reason, ''), uploaded_at, reviewed_at`

// DriverKYCRepository persists a driver's onboarding documents: the uploaded
// images' metadata, the typed profile fields on `drivers`, and payout details.
// Image bytes are not its concern — those live in internal/storage, and this
// table only holds the key that finds them.
type DriverKYCRepository struct {
	pool *pgxpool.Pool
}

// NewDriverKYCRepository wires the repository to a connection pool.
func NewDriverKYCRepository(pool *pgxpool.Pool) *DriverKYCRepository {
	return &DriverKYCRepository{pool: pool}
}

// UpsertDocumentParams carries one uploaded image's metadata.
type UpsertDocumentParams struct {
	Kind        domain.DocumentKind
	ObjectKey   string
	ContentType string
	ByteSize    int64
	SHA256      string
}

// UpsertDocument records an uploaded image, replacing any previous one of the
// same kind. It returns the stored row along with the object key it displaced
// (empty on a first upload) so the caller can delete the now-orphaned bytes.
//
// A retake resets review state: the reviewer has not seen this image, so
// status goes back to pending and any rejection reason is cleared.
func (r *DriverKYCRepository) UpsertDocument(
	ctx context.Context, driverID string, p UpsertDocumentParams,
) (domain.DriverDocument, string, error) {
	// The old key must be read in the same statement that overwrites it,
	// otherwise a concurrent retake could leave one image's bytes orphaned in
	// storage with nothing pointing at them.
	const q = `
		WITH previous AS (
			SELECT object_key FROM driver_documents
			WHERE driver_id = $1 AND kind = $2
		), upserted AS (
			INSERT INTO driver_documents
				(driver_id, kind, object_key, content_type, byte_size, sha256)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (driver_id, kind) DO UPDATE SET
				object_key    = EXCLUDED.object_key,
				content_type  = EXCLUDED.content_type,
				byte_size     = EXCLUDED.byte_size,
				sha256        = EXCLUDED.sha256,
				status        = 'pending',
				reject_reason = NULL,
				uploaded_at   = now(),
				reviewed_at   = NULL
			RETURNING ` + documentColumns + `
		)
		SELECT upserted.*, coalesce((SELECT object_key FROM previous), '')
		FROM upserted`

	var (
		d           domain.DriverDocument
		previousKey string
	)
	err := r.pool.QueryRow(ctx, q,
		driverID, p.Kind, p.ObjectKey, p.ContentType, p.ByteSize, p.SHA256,
	).Scan(
		&d.ID, &d.Kind, &d.ObjectKey, &d.ContentType, &d.ByteSize, &d.SHA256,
		&d.Status, &d.RejectReason, &d.UploadedAt, &d.ReviewedAt, &previousKey,
	)
	if err != nil {
		return domain.DriverDocument{}, "", fmt.Errorf("saving document: %w", err)
	}
	// An unchanged key means the driver re-uploaded onto the same object;
	// reporting it as displaced would delete the bytes we just stored.
	if previousKey == d.ObjectKey {
		previousKey = ""
	}
	return d, previousKey, nil
}

// ListDocuments returns every document a driver has uploaded, in the order the
// app's Document View asks for them.
func (r *DriverKYCRepository) ListDocuments(ctx context.Context, driverID string) ([]domain.DriverDocument, error) {
	const q = `SELECT ` + documentColumns + `
		FROM driver_documents WHERE driver_id = $1 ORDER BY uploaded_at`

	rows, err := r.pool.Query(ctx, q, driverID)
	if err != nil {
		return nil, fmt.Errorf("listing documents: %w", err)
	}
	defer rows.Close()

	docs := make([]domain.DriverDocument, 0, len(domain.DocumentKinds))
	for rows.Next() {
		var d domain.DriverDocument
		if err := rows.Scan(
			&d.ID, &d.Kind, &d.ObjectKey, &d.ContentType, &d.ByteSize, &d.SHA256,
			&d.Status, &d.RejectReason, &d.UploadedAt, &d.ReviewedAt,
		); err != nil {
			return nil, fmt.Errorf("scanning document: %w", err)
		}
		docs = append(docs, d)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("reading documents: %w", err)
	}
	return docs, nil
}

// FindDocument returns one of a driver's documents, or [ErrDocumentNotFound].
func (r *DriverKYCRepository) FindDocument(
	ctx context.Context, driverID string, kind domain.DocumentKind,
) (domain.DriverDocument, error) {
	const q = `SELECT ` + documentColumns + `
		FROM driver_documents WHERE driver_id = $1 AND kind = $2`

	var d domain.DriverDocument
	err := r.pool.QueryRow(ctx, q, driverID, kind).Scan(
		&d.ID, &d.Kind, &d.ObjectKey, &d.ContentType, &d.ByteSize, &d.SHA256,
		&d.Status, &d.RejectReason, &d.UploadedAt, &d.ReviewedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.DriverDocument{}, ErrDocumentNotFound
	}
	if err != nil {
		return domain.DriverDocument{}, fmt.Errorf("finding document: %w", err)
	}
	return d, nil
}

// UpdateProfileParams carries the typed KYC fields. Every field is a pointer
// because the Document View submits one step at a time: nil means "this step
// didn't touch it", which is different from "clear it".
type UpdateProfileParams struct {
	FullName             *string
	DateOfBirth          *time.Time
	Gender               *string
	Transmission         *string
	AadhaarLast4         *string
	AadhaarFingerprint   *string
	DrivingLicenseNumber *string
}

// UpdateProfile applies a step's fields to the driver row, leaving the rest
// untouched. A duplicate Aadhaar maps to [ErrAadhaarTaken].
func (r *DriverKYCRepository) UpdateProfile(ctx context.Context, driverID string, p UpdateProfileParams) error {
	const q = `
		UPDATE drivers SET
			name                   = coalesce($2, name),
			date_of_birth          = coalesce($3, date_of_birth),
			gender                 = coalesce($4, gender),
			transmission           = coalesce($5, transmission),
			aadhaar_last4          = coalesce($6, aadhaar_last4),
			aadhaar_fingerprint    = coalesce($7, aadhaar_fingerprint),
			driving_license_number = coalesce($8, driving_license_number)
		WHERE id = $1`

	tag, err := r.pool.Exec(ctx, q, driverID,
		p.FullName, p.DateOfBirth, p.Gender, p.Transmission,
		p.AadhaarLast4, p.AadhaarFingerprint, p.DrivingLicenseNumber,
	)
	if err != nil {
		pgErr, ok := errors.AsType[*pgconn.PgError](err)
		if ok && pgErr.Code == uniqueViolation && pgErr.ConstraintName == aadhaarFingerprintIndex {
			return ErrAadhaarTaken
		}
		return fmt.Errorf("updating driver profile: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrDriverNotFound
	}
	return nil
}

// SetKYCStatus moves the driver's overall onboarding state. Pass recordSubmission
// on the transition into review; the timestamp is only written the first time,
// so re-submitting doesn't rewrite when the driver originally finished.
//
// The time comes from the database rather than the caller, so it can't be
// ordered inconsistently against uploaded_at and updated_at on neighbouring
// rows, which are also database clock.
func (r *DriverKYCRepository) SetKYCStatus(
	ctx context.Context, driverID string, status domain.KYCStatus, recordSubmission bool,
) error {
	const q = `
		UPDATE drivers
		SET kyc_status = $2,
		    kyc_submitted_at = CASE
		        WHEN $3 THEN coalesce(kyc_submitted_at, now())
		        ELSE kyc_submitted_at
		    END
		WHERE id = $1`

	tag, err := r.pool.Exec(ctx, q, driverID, status, recordSubmission)
	if err != nil {
		return fmt.Errorf("updating kyc status: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrDriverNotFound
	}
	return nil
}

// FindProfile returns the driver's typed KYC fields, or [ErrDriverNotFound].
func (r *DriverKYCRepository) FindProfile(ctx context.Context, driverID string) (domain.DriverProfile, error) {
	const q = `
		SELECT name, date_of_birth, coalesce(gender, ''), transmission,
		       coalesce(aadhaar_last4, ''), coalesce(driving_license_number, ''),
		       kyc_status, kyc_submitted_at
		FROM drivers WHERE id = $1`

	var p domain.DriverProfile
	err := r.pool.QueryRow(ctx, q, driverID).Scan(
		&p.FullName, &p.DateOfBirth, &p.Gender, &p.Transmission,
		&p.AadhaarLast4, &p.DrivingLicenseNumber, &p.KYCStatus, &p.KYCSubmittedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.DriverProfile{}, ErrDriverNotFound
	}
	if err != nil {
		return domain.DriverProfile{}, fmt.Errorf("finding driver profile: %w", err)
	}
	return p, nil
}

// UpsertBankAccountParams carries payout details. AccountNumberEncrypted is
// sealed by the service — this layer never sees the number in the clear.
type UpsertBankAccountParams struct {
	AccountHolderName      string
	AccountNumberEncrypted []byte
	AccountNumberLast4     string
	IFSCCode               string
}

// UpsertBankAccount saves or replaces a driver's payout details.
func (r *DriverKYCRepository) UpsertBankAccount(
	ctx context.Context, driverID string, p UpsertBankAccountParams,
) (domain.DriverBankAccount, error) {
	const q = `
		INSERT INTO driver_bank_accounts
			(driver_id, account_holder_name, account_number_encrypted,
			 account_number_last4, ifsc_code)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (driver_id) DO UPDATE SET
			account_holder_name      = EXCLUDED.account_holder_name,
			account_number_encrypted = EXCLUDED.account_number_encrypted,
			account_number_last4     = EXCLUDED.account_number_last4,
			ifsc_code                = EXCLUDED.ifsc_code,
			updated_at               = now()
		RETURNING account_holder_name, account_number_last4, ifsc_code, updated_at`

	var a domain.DriverBankAccount
	err := r.pool.QueryRow(ctx, q, driverID,
		p.AccountHolderName, p.AccountNumberEncrypted, p.AccountNumberLast4, p.IFSCCode,
	).Scan(&a.AccountHolderName, &a.AccountNumberLast4, &a.IFSCCode, &a.UpdatedAt)
	if err != nil {
		return domain.DriverBankAccount{}, fmt.Errorf("saving bank account: %w", err)
	}
	return a, nil
}

// FindBankAccount returns a driver's payout details without the account
// number, or [ErrBankAccountNotFound].
func (r *DriverKYCRepository) FindBankAccount(ctx context.Context, driverID string) (domain.DriverBankAccount, error) {
	const q = `
		SELECT account_holder_name, account_number_last4, ifsc_code, updated_at
		FROM driver_bank_accounts WHERE driver_id = $1`

	var a domain.DriverBankAccount
	err := r.pool.QueryRow(ctx, q, driverID).
		Scan(&a.AccountHolderName, &a.AccountNumberLast4, &a.IFSCCode, &a.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.DriverBankAccount{}, ErrBankAccountNotFound
	}
	if err != nil {
		return domain.DriverBankAccount{}, fmt.Errorf("finding bank account: %w", err)
	}
	return a, nil
}
