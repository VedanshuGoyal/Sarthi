package domain

// AccountKind names which of the two account tables an erasure targets.
type AccountKind string

const (
	AccountCustomer AccountKind = "customer" // users
	AccountDriver   AccountKind = "driver"   // drivers
)

// ErasedName is what an erased account's name reads as everywhere it is
// still shown (a driver's past rides, a customer's ride history).
const ErasedName = "Deleted user"

// ErasureBlockers is what stands in the way of erasing an account right
// now, read under the account's lock.
type ErasureBlockers struct {
	// ActiveRides are accepted, arrived or in progress.
	ActiveRides int
	// UnpaidRides are completed with a fare and not yet paid.
	UnpaidRides int
}

// StoredDocument is one KYC image to delete: its row and its bucket key.
type StoredDocument struct {
	ID        string
	DriverID  string
	ObjectKey string
}

// ErasureResult is what the store did inside the erasure transaction.
type ErasureResult struct {
	// AlreadyErased reports the account had been erased before; the
	// cleanup ran again.
	AlreadyErased bool
	// CancelledRequests are the customer's bookings no driver had taken
	// yet, cancelled so no driver turns up for a deleted account.
	CancelledRequests int
	// Documents are the driver's KYC images, still to delete from the
	// bucket and then from driver_documents.
	Documents []StoredDocument
}

// ErasureReport is the outcome of an erasure, as the API returns it.
type ErasureReport struct {
	Kind              AccountKind `json:"kind"`
	ID                string      `json:"id"`
	Status            string      `json:"status"` // always "erased"
	AlreadyErased     bool        `json:"alreadyErased,omitempty"`
	CancelledRequests int         `json:"cancelledRequests,omitempty"`
	DocumentsDeleted  int         `json:"documentsDeleted,omitempty"`
	// DocumentsPending failed to delete from the bucket; the daily
	// retention sweep retries them.
	DocumentsPending int `json:"documentsPending,omitempty"`
}

// RetentionReport counts what one retention sweep deleted.
type RetentionReport struct {
	Sessions        int64 `json:"sessions"`
	KYCChecks       int64 `json:"kycChecks"`
	ErasedDocuments int   `json:"erasedDocuments"`
}
