package service

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// Retention periods (docs/privacy/data-map.md lists them all).
const (
	// ExpiredSessionGrace is how long an expired session row is kept, for
	// "why was I signed out" questions, before it is deleted.
	ExpiredSessionGrace = 7 * 24 * time.Hour
	// KYCCheckRetention is how long the KYC provider-call log is kept: the
	// cost audit and the daily per-driver limit only need recent rows.
	KYCCheckRetention = 180 * 24 * time.Hour
	// RetentionInterval is how often the sweep runs.
	RetentionInterval = 24 * time.Hour
)

// RetentionStore deletes rows past their retention
// (repository.RetentionRepository).
type RetentionStore interface {
	DeleteSessionsExpiredBefore(ctx context.Context, cutoff time.Time) (int64, error)
	DeleteKYCChecksBefore(ctx context.Context, cutoff time.Time) (int64, error)
}

// ErasedDocumentFinisher retries KYC images left behind by an erasure
// ([ErasureService]).
type ErasedDocumentFinisher interface {
	FinishErasedDocuments(ctx context.Context) (int, error)
}

// RetentionService deletes personal data once it is no longer needed, once
// a day. OTP codes, OTP attempt counters and live locations are memory-only
// (memstore) and never reach the database, so there is nothing to sweep for
// them.
type RetentionService struct {
	store    RetentionStore
	erasures ErasedDocumentFinisher // may be nil
	every    time.Duration
	now      func() time.Time // seam for tests
}

// NewRetentionService builds the sweep over store; erasures, when set, also
// finishes erasures whose bucket deletes failed.
func NewRetentionService(store RetentionStore, erasures ErasedDocumentFinisher) *RetentionService {
	return &RetentionService{store: store, erasures: erasures, every: RetentionInterval, now: time.Now}
}

// Sweep runs every retention rule once. A failing rule doesn't stop the
// others; their errors are joined.
func (s *RetentionService) Sweep(ctx context.Context) (domain.RetentionReport, error) {
	now := s.now()
	var (
		report domain.RetentionReport
		errs   []error
		err    error
	)
	if report.Sessions, err = s.store.DeleteSessionsExpiredBefore(ctx, now.Add(-ExpiredSessionGrace)); err != nil {
		errs = append(errs, err)
	}
	if report.KYCChecks, err = s.store.DeleteKYCChecksBefore(ctx, now.Add(-KYCCheckRetention)); err != nil {
		errs = append(errs, err)
	}
	if s.erasures != nil {
		if report.ErasedDocuments, err = s.erasures.FinishErasedDocuments(ctx); err != nil {
			errs = append(errs, err)
		}
	}
	return report, errors.Join(errs...)
}

// Run sweeps now and then every interval until ctx is cancelled.
func (s *RetentionService) Run(ctx context.Context) {
	ticker := time.NewTicker(s.every)
	defer ticker.Stop()
	for {
		report, err := s.Sweep(ctx)
		if err != nil {
			slog.ErrorContext(ctx, "retention: sweep", "error", err)
		}
		slog.InfoContext(ctx, "retention: swept", "sessions", report.Sessions,
			"kycChecks", report.KYCChecks, "erasedDocuments", report.ErasedDocuments)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
