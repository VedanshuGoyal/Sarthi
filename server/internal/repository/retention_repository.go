package repository

import (
	"context"
	"fmt"
	"time"
)

// RetentionRepository deletes rows that have outlived their retention
// period (service/retention_service.go sets the periods).
type RetentionRepository struct {
	db DB
}

// NewRetentionRepository wires the repository to a pool (or a test's tx).
func NewRetentionRepository(db DB) *RetentionRepository {
	return &RetentionRepository{db: db}
}

// DeleteSessionsExpiredBefore deletes customer and driver sessions that
// expired before cutoff, returning how many went.
func (r *RetentionRepository) DeleteSessionsExpiredBefore(ctx context.Context, cutoff time.Time) (int64, error) {
	var n int64
	for _, q := range []string{
		`DELETE FROM sessions WHERE expires_at < $1`,
		`DELETE FROM driver_sessions WHERE expires_at < $1`,
	} {
		tag, err := r.db.Exec(ctx, q, cutoff)
		if err != nil {
			return n, fmt.Errorf("deleting expired sessions: %w", err)
		}
		n += tag.RowsAffected()
	}
	return n, nil
}

// DeleteKYCChecksBefore deletes the KYC provider-call log older than cutoff.
func (r *RetentionRepository) DeleteKYCChecksBefore(ctx context.Context, cutoff time.Time) (int64, error) {
	tag, err := r.db.Exec(ctx, `DELETE FROM driver_kyc_checks WHERE created_at < $1`, cutoff)
	if err != nil {
		return 0, fmt.Errorf("deleting old KYC checks: %w", err)
	}
	return tag.RowsAffected(), nil
}
