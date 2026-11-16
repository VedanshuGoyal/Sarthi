package service

import (
	"context"
	"errors"
	"log/slog"
	"regexp"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// ErrAccountBusy is matched by every [AccountBusyError].
var ErrAccountBusy = errors.New("this account can't be deleted right now")

// ErrUnknownAccountKind is returned for an erasure kind other than customer
// or driver.
var ErrUnknownAccountKind = errors.New("kind must be customer or driver")

// AccountBusyError says why an account can't be erased yet, in words for the
// person asking. It matches [ErrAccountBusy].
type AccountBusyError struct {
	Reason string
}

func (e *AccountBusyError) Error() string { return e.Reason }

// Is makes errors.Is(err, ErrAccountBusy) hold.
func (e *AccountBusyError) Is(target error) bool { return target == ErrAccountBusy }

// ErasureStore is the persistence an erasure needs
// (repository.ErasureRepository).
type ErasureStore interface {
	EraseUser(ctx context.Context, userID string, at time.Time, allow func(domain.ErasureBlockers) error) (domain.ErasureResult, error)
	EraseDriver(ctx context.Context, driverID string, at time.Time, allow func(domain.ErasureBlockers) error) (domain.ErasureResult, error)
	DeleteDocument(ctx context.Context, documentID string) error
	ErasedDriverDocuments(ctx context.Context, limit int) ([]domain.StoredDocument, error)
}

// AllSessionsRevoker ends every session of an account ([SessionService]).
type AllSessionsRevoker interface {
	RevokeAll(ctx context.Context, userID string) error
}

// BlobDeleter removes an object from the KYC bucket (storage.Blob).
type BlobDeleter interface {
	Delete(ctx context.Context, key string) error
}

// PresenceRemover takes a driver off the online index (memstore.DriverTracker).
type PresenceRemover interface {
	Remove(driverID string)
}

// erasedDocumentsBatch caps how many leftover images one sweep deletes.
const erasedDocumentsBatch = 200

// uuidRe matches an account id; anything else can't name an account.
var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// ErasureService deletes a person's data on request (DPDP right to
// erasure). It anonymises rather than deletes the account row: bookings and
// payments must survive (0018), and a driver's unpaid earnings stay payable
// from the back office. Everything else about the person goes: sessions in
// the database and the memstore cache, push tokens, saved cars, recent
// pickups and, for drivers, KYC images and their rows, bank details and
// verification fields.
type ErasureService struct {
	store          ErasureStore
	userSessions   AllSessionsRevoker
	driverSessions AllSessionsRevoker
	blobs          BlobDeleter
	presence       PresenceRemover
	now            func() time.Time // seam for tests
}

// NewErasureService wires erasure over its store, both apps' sessions, the
// KYC bucket and the online-driver index. presence may be nil.
func NewErasureService(
	store ErasureStore, userSessions, driverSessions AllSessionsRevoker, blobs BlobDeleter, presence PresenceRemover,
) *ErasureService {
	return &ErasureService{
		store: store, userSessions: userSessions, driverSessions: driverSessions,
		blobs: blobs, presence: presence, now: time.Now,
	}
}

// Erase erases the account of kind with id. It is refused with an
// [AccountBusyError] while the account has a ride accepted, arrived or in
// progress, or a completed ride not yet paid; [repository.ErrAccountNotFound]
// if there is no such account. Erasing an erased account runs the cleanup
// again (it is how a failed bucket delete is retried by hand).
//
// A KYC image the bucket fails to delete is logged and counted in
// DocumentsPending, not returned as an error: the account is erased by then,
// and the daily retention sweep retries the image.
func (s *ErasureService) Erase(ctx context.Context, kind domain.AccountKind, id string) (domain.ErasureReport, error) {
	if !uuidRe.MatchString(id) {
		return domain.ErasureReport{}, repository.ErrAccountNotFound
	}
	report := domain.ErasureReport{Kind: kind, ID: id, Status: "erased"}
	var (
		res      domain.ErasureResult
		err      error
		sessions AllSessionsRevoker
	)
	switch kind {
	case domain.AccountCustomer:
		res, err = s.store.EraseUser(ctx, id, s.now(), customerMayErase)
		sessions = s.userSessions
	case domain.AccountDriver:
		res, err = s.store.EraseDriver(ctx, id, s.now(), driverMayErase)
		sessions = s.driverSessions
	default:
		return domain.ErasureReport{}, ErrUnknownAccountKind
	}
	if err != nil {
		return domain.ErasureReport{}, err
	}
	report.AlreadyErased = res.AlreadyErased
	report.CancelledRequests = res.CancelledRequests

	// The transaction deleted the session rows; this drops the cached copies
	// too, which is what makes the old tokens fail now rather than at the
	// next restart.
	if err := sessions.RevokeAll(ctx, id); err != nil {
		slog.ErrorContext(ctx, "erasure: revoking sessions", "kind", kind, "id", id, "error", err)
	}
	if kind == domain.AccountDriver && s.presence != nil {
		s.presence.Remove(id)
	}
	report.DocumentsDeleted, report.DocumentsPending = s.deleteDocuments(ctx, res.Documents)
	slog.InfoContext(ctx, "erasure: account erased", "kind", kind, "id", id,
		"again", res.AlreadyErased, "cancelledRequests", res.CancelledRequests,
		"documentsDeleted", report.DocumentsDeleted, "documentsPending", report.DocumentsPending)
	return report, nil
}

// FinishErasedDocuments deletes KYC images still held for erased drivers,
// whose bucket delete failed during the erasure. Run by the retention sweep.
func (s *ErasureService) FinishErasedDocuments(ctx context.Context) (int, error) {
	docs, err := s.store.ErasedDriverDocuments(ctx, erasedDocumentsBatch)
	if err != nil {
		return 0, err
	}
	deleted, pending := s.deleteDocuments(ctx, docs)
	if pending > 0 {
		return deleted, errors.New("some erased drivers' KYC images could not be deleted; see the log")
	}
	return deleted, nil
}

// deleteDocuments removes each image from the bucket and then its row, so a
// row is only ever lost together with its object.
func (s *ErasureService) deleteDocuments(ctx context.Context, docs []domain.StoredDocument) (deleted, pending int) {
	for _, d := range docs {
		if err := s.blobs.Delete(ctx, d.ObjectKey); err != nil {
			slog.ErrorContext(ctx, "erasure: deleting a KYC image from the bucket; the retention sweep retries it",
				"driverID", d.DriverID, "documentID", d.ID, "error", err)
			pending++
			continue
		}
		if err := s.store.DeleteDocument(ctx, d.ID); err != nil {
			slog.ErrorContext(ctx, "erasure: deleting a KYC image's row",
				"driverID", d.DriverID, "documentID", d.ID, "error", err)
			pending++
			continue
		}
		deleted++
	}
	return deleted, pending
}

// customerMayErase is the rule for a customer: no driver on the way or
// driving, and nothing left to pay.
func customerMayErase(b domain.ErasureBlockers) error {
	switch {
	case b.ActiveRides > 0:
		return &AccountBusyError{Reason: "A driver has your ride. Cancel it or wait until it ends, then delete your account."}
	case b.UnpaidRides > 0:
		return &AccountBusyError{Reason: "Pay for your completed ride first, then delete your account."}
	}
	return nil
}

// driverMayErase is the rule for a driver: no ride held, and no completed
// ride the customer still has to pay for (the driver's share isn't settled).
func driverMayErase(b domain.ErasureBlockers) error {
	switch {
	case b.ActiveRides > 0:
		return &AccountBusyError{Reason: "You have a ride accepted or in progress. Finish it or hand it back, then delete your account."}
	case b.UnpaidRides > 0:
		return &AccountBusyError{Reason: "A customer hasn't paid for a ride you drove yet. Try again once it's paid, or contact support."}
	}
	return nil
}
