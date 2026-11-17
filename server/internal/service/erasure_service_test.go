package service

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

const (
	erasedCustomerID = "11111111-1111-4111-8111-111111111111"
	erasedDriverID   = "22222222-2222-4222-8222-222222222222"
)

// fakeErasureStore stands in for repository.ErasureRepository: blockers is
// what the locked read would find; erased records which accounts were
// anonymised; docs are the driver's KYC rows.
type fakeErasureStore struct {
	blockers   domain.ErasureBlockers
	missing    bool
	erased     []string
	erasedAt   time.Time
	docs       []domain.StoredDocument
	deletedDoc []string
	storeErr   error
}

func (f *fakeErasureStore) erase(id string, at time.Time, allow func(domain.ErasureBlockers) error) (domain.ErasureResult, error) {
	if f.missing {
		return domain.ErasureResult{}, repository.ErrAccountNotFound
	}
	if f.storeErr != nil {
		return domain.ErasureResult{}, f.storeErr
	}
	if err := allow(f.blockers); err != nil {
		return domain.ErasureResult{}, err
	}
	again := slices.Contains(f.erased, id)
	f.erased, f.erasedAt = append(f.erased, id), at
	return domain.ErasureResult{AlreadyErased: again, CancelledRequests: 1, Documents: f.remaining()}, nil
}

func (f *fakeErasureStore) remaining() []domain.StoredDocument {
	var out []domain.StoredDocument
	for _, d := range f.docs {
		if !slices.Contains(f.deletedDoc, d.ID) {
			out = append(out, d)
		}
	}
	return out
}

func (f *fakeErasureStore) EraseUser(_ context.Context, id string, at time.Time, allow func(domain.ErasureBlockers) error) (domain.ErasureResult, error) {
	res, err := f.erase(id, at, allow)
	res.Documents = nil // customers have no KYC images
	return res, err
}

func (f *fakeErasureStore) EraseDriver(_ context.Context, id string, at time.Time, allow func(domain.ErasureBlockers) error) (domain.ErasureResult, error) {
	return f.erase(id, at, allow)
}

func (f *fakeErasureStore) DeleteDocument(_ context.Context, id string) error {
	f.deletedDoc = append(f.deletedDoc, id)
	return nil
}

func (f *fakeErasureStore) ErasedDriverDocuments(context.Context, int) ([]domain.StoredDocument, error) {
	return f.remaining(), nil
}

type fakeAllRevoker struct{ revoked []string }

func (f *fakeAllRevoker) RevokeAll(_ context.Context, id string) error {
	f.revoked = append(f.revoked, id)
	return nil
}

// fakeKYCBucket fails Delete for keys in failing.
type fakeKYCBucket struct {
	deleted []string
	failing map[string]bool
}

func (f *fakeKYCBucket) Delete(_ context.Context, key string) error {
	if f.failing[key] {
		return errors.New("bucket unavailable")
	}
	f.deleted = append(f.deleted, key)
	return nil
}

type fakeOnlineIndex struct{ removed []string }

func (f *fakeOnlineIndex) Remove(id string) { f.removed = append(f.removed, id) }

type erasureRig struct {
	store          *fakeErasureStore
	users, drivers *fakeAllRevoker
	blobs          *fakeKYCBucket
	presence       *fakeOnlineIndex
	svc            *ErasureService
	now            time.Time
}

func newErasureRig() *erasureRig {
	r := &erasureRig{
		store: &fakeErasureStore{docs: []domain.StoredDocument{
			{ID: "doc-1", DriverID: erasedDriverID, ObjectKey: "drivers/" + erasedDriverID + "/selfie/a.jpg"},
			{ID: "doc-2", DriverID: erasedDriverID, ObjectKey: "drivers/" + erasedDriverID + "/aadhaar/b.jpg"},
		}},
		users: &fakeAllRevoker{}, drivers: &fakeAllRevoker{},
		blobs: &fakeKYCBucket{failing: map[string]bool{}}, presence: &fakeOnlineIndex{},
		now: time.Date(2026, 11, 17, 22, 0, 0, 0, time.UTC),
	}
	r.svc = NewErasureService(r.store, r.users, r.drivers, r.blobs, r.presence)
	r.svc.now = func() time.Time { return r.now }
	return r
}

func TestErasure_CustomerIsAnonymisedAndSignedOutEverywhere(t *testing.T) {
	r := newErasureRig()
	report, err := r.svc.Erase(context.Background(), domain.AccountCustomer, erasedCustomerID)
	if err != nil {
		t.Fatalf("Erase: %v", err)
	}
	if report.Status != "erased" || report.Kind != domain.AccountCustomer || report.ID != erasedCustomerID {
		t.Errorf("report = %+v", report)
	}
	if !slices.Equal(r.store.erased, []string{erasedCustomerID}) || !r.store.erasedAt.Equal(r.now) {
		t.Errorf("store erased %v at %v", r.store.erased, r.store.erasedAt)
	}
	if !slices.Equal(r.users.revoked, []string{erasedCustomerID}) || len(r.drivers.revoked) != 0 {
		t.Errorf("revoked customers %v, drivers %v", r.users.revoked, r.drivers.revoked)
	}
	if len(r.blobs.deleted) != 0 || len(r.presence.removed) != 0 {
		t.Error("a customer erasure touched KYC images or the online index")
	}
}

func TestErasure_DriverLosesImagesSessionsAndPresence(t *testing.T) {
	r := newErasureRig()
	report, err := r.svc.Erase(context.Background(), domain.AccountDriver, erasedDriverID)
	if err != nil {
		t.Fatalf("Erase: %v", err)
	}
	if report.DocumentsDeleted != 2 || report.DocumentsPending != 0 {
		t.Errorf("report = %+v, want 2 deleted", report)
	}
	if len(r.blobs.deleted) != 2 || !slices.Equal(r.store.deletedDoc, []string{"doc-1", "doc-2"}) {
		t.Errorf("bucket deletes %v, row deletes %v", r.blobs.deleted, r.store.deletedDoc)
	}
	if !slices.Equal(r.drivers.revoked, []string{erasedDriverID}) || len(r.users.revoked) != 0 {
		t.Errorf("revoked drivers %v, customers %v", r.drivers.revoked, r.users.revoked)
	}
	if !slices.Equal(r.presence.removed, []string{erasedDriverID}) {
		t.Errorf("presence removed %v", r.presence.removed)
	}
}

// A bucket failure must not lose the row that names the object: it stays
// for the retention sweep, which deletes it once the bucket is back.
func TestErasure_AFailedBucketDeleteKeepsTheRowForTheSweep(t *testing.T) {
	r := newErasureRig()
	failing := r.store.docs[1]
	r.blobs.failing[failing.ObjectKey] = true

	report, err := r.svc.Erase(context.Background(), domain.AccountDriver, erasedDriverID)
	if err != nil {
		t.Fatalf("Erase: %v (the account is erased; the image is retried later)", err)
	}
	if report.DocumentsDeleted != 1 || report.DocumentsPending != 1 {
		t.Errorf("report = %+v, want 1 deleted, 1 pending", report)
	}
	if slices.Contains(r.store.deletedDoc, failing.ID) {
		t.Fatal("the row of an image still in the bucket was deleted")
	}

	if n, err := r.svc.FinishErasedDocuments(context.Background()); err == nil || n != 0 {
		t.Errorf("sweep while the bucket still fails: %d, %v; want 0 and an error", n, err)
	}
	delete(r.blobs.failing, failing.ObjectKey)
	if n, err := r.svc.FinishErasedDocuments(context.Background()); err != nil || n != 1 {
		t.Errorf("sweep once the bucket is back: %d, %v; want 1, nil", n, err)
	}
	if len(r.store.remaining()) != 0 {
		t.Errorf("images left: %v", r.store.remaining())
	}
}

func TestErasure_RefusedWhileARideIsOpenOrUnpaid(t *testing.T) {
	for _, tc := range []struct {
		kind     domain.AccountKind
		id       string
		blockers domain.ErasureBlockers
		says     string
	}{
		{domain.AccountCustomer, erasedCustomerID, domain.ErasureBlockers{ActiveRides: 1}, "driver has your ride"},
		{domain.AccountCustomer, erasedCustomerID, domain.ErasureBlockers{UnpaidRides: 1}, "Pay for"},
		{domain.AccountDriver, erasedDriverID, domain.ErasureBlockers{ActiveRides: 1}, "accepted or in progress"},
		{domain.AccountDriver, erasedDriverID, domain.ErasureBlockers{UnpaidRides: 2}, "hasn't paid"},
		{domain.AccountDriver, erasedDriverID, domain.ErasureBlockers{AwaitingPayout: 1}, "earnings waiting for a payout"},
	} {
		r := newErasureRig()
		r.store.blockers = tc.blockers
		_, err := r.svc.Erase(context.Background(), tc.kind, tc.id)
		var busy *AccountBusyError
		if !errors.Is(err, ErrAccountBusy) || !errors.As(err, &busy) || !strings.Contains(busy.Reason, tc.says) {
			t.Errorf("%s %+v: err = %v, want busy saying %q", tc.kind, tc.blockers, err, tc.says)
		}
		if len(r.store.erased)+len(r.users.revoked)+len(r.drivers.revoked)+len(r.blobs.deleted) != 0 {
			t.Errorf("%s %+v: something was erased while refused", tc.kind, tc.blockers)
		}
	}
}

// With no payment gateway a customer has no way to pay in the app, so an
// unpaid ride doesn't stop them deleting their account. Anything else still
// does, and a driver is still held: their share is settled by hand.
func TestErasure_PaymentsOffIgnoresTheCustomersUnpaidRide(t *testing.T) {
	r := newErasureRig()
	r.svc.SetPaymentsEnabled(false)
	r.store.blockers = domain.ErasureBlockers{UnpaidRides: 1}
	if _, err := r.svc.Erase(context.Background(), domain.AccountCustomer, erasedCustomerID); err != nil {
		t.Errorf("customer: err = %v, want erased", err)
	}

	for _, tc := range []struct {
		kind     domain.AccountKind
		id       string
		blockers domain.ErasureBlockers
	}{
		{domain.AccountCustomer, erasedCustomerID, domain.ErasureBlockers{UnpaidRides: 1, ActiveRides: 1}},
		{domain.AccountDriver, erasedDriverID, domain.ErasureBlockers{UnpaidRides: 1}},
	} {
		r := newErasureRig()
		r.svc.SetPaymentsEnabled(false)
		r.store.blockers = tc.blockers
		if _, err := r.svc.Erase(context.Background(), tc.kind, tc.id); !errors.Is(err, ErrAccountBusy) {
			t.Errorf("%s %+v: err = %v, want busy", tc.kind, tc.blockers, err)
		}
	}
}

func TestErasure_UnknownAccountsAndKinds(t *testing.T) {
	r := newErasureRig()
	if _, err := r.svc.Erase(context.Background(), domain.AccountCustomer, "not-a-uuid"); !errors.Is(err, repository.ErrAccountNotFound) {
		t.Errorf("malformed id: err = %v, want ErrAccountNotFound", err)
	}
	if _, err := r.svc.Erase(context.Background(), "robot", erasedCustomerID); !errors.Is(err, ErrUnknownAccountKind) {
		t.Errorf("unknown kind: err = %v, want ErrUnknownAccountKind", err)
	}
	r.store.missing = true
	if _, err := r.svc.Erase(context.Background(), domain.AccountDriver, erasedDriverID); !errors.Is(err, repository.ErrAccountNotFound) {
		t.Errorf("no such driver: err = %v, want ErrAccountNotFound", err)
	}
	if len(r.drivers.revoked) != 0 {
		t.Error("sessions revoked for an account that doesn't exist")
	}
}

// A database failure leaves the account as it was and signs nobody out.
func TestErasure_StoreFailureChangesNothingElse(t *testing.T) {
	r := newErasureRig()
	r.store.storeErr = errors.New("db down")
	if _, err := r.svc.Erase(context.Background(), domain.AccountDriver, erasedDriverID); err == nil {
		t.Fatal("Erase hid the store's error")
	}
	if len(r.drivers.revoked)+len(r.blobs.deleted)+len(r.presence.removed) != 0 {
		t.Error("sessions, images or presence were touched although the erasure failed")
	}
}

func TestErasure_ErasingAgainReportsIt(t *testing.T) {
	r := newErasureRig()
	ctx := context.Background()
	if _, err := r.svc.Erase(ctx, domain.AccountCustomer, erasedCustomerID); err != nil {
		t.Fatal(err)
	}
	report, err := r.svc.Erase(ctx, domain.AccountCustomer, erasedCustomerID)
	if err != nil || !report.AlreadyErased {
		t.Errorf("second erase: %+v, %v; want AlreadyErased", report, err)
	}
}
