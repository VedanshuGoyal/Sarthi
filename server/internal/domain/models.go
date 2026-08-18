// Package domain holds the core, transport-agnostic types of the Sarthi
// platform. These structs are the shared vocabulary used by every layer
// (api, websocket, memstore, repository, service) so they intentionally
// carry no behaviour beyond JSON tags.
package domain

import "time"

// User is a registered customer of the platform. It is persisted in PostgreSQL
// (the source of truth for accounts) and created during phone-number
// registration. DateOfBirth is stored as a calendar date; CreatedAt is set by
// the database.
type User struct {
	ID          string    `json:"id"`
	PhoneE164   string    `json:"phoneE164"`
	Name        string    `json:"name"`
	Email       string    `json:"email"`
	DateOfBirth time.Time `json:"dateOfBirth"`
	CreatedAt   time.Time `json:"createdAt"`
}

// Session is an authenticated login: an opaque bearer token bound to a user.
// PostgreSQL is the source of truth (so sessions survive a restart); the server
// caches live sessions in memstore for fast validation. A token is valid until
// ExpiresAt.
type Session struct {
	Token     string    `json:"token"`
	UserID    string    `json:"userId"`
	CreatedAt time.Time `json:"createdAt"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// DriverStatus is the availability of a driver for matching.
type DriverStatus string

const (
	DriverStatusOffline   DriverStatus = "offline"   // not accepting jobs
	DriverStatusAvailable DriverStatus = "available" // online, can be matched
	DriverStatusOnTrip    DriverStatus = "on_trip"   // online but busy
)

// RideStatus tracks a ride through its lifecycle.
type RideStatus string

const (
	RideStatusRequested  RideStatus = "requested"   // rider asked, no driver yet
	RideStatusMatched    RideStatus = "matched"     // offered to a driver
	RideStatusAccepted   RideStatus = "accepted"    // driver accepted, en route
	RideStatusArrived    RideStatus = "arrived"     // driver at pickup
	RideStatusInProgress RideStatus = "in_progress" // rider on board
	RideStatusCompleted  RideStatus = "completed"   // finished, fare settled
	RideStatusCancelled  RideStatus = "cancelled"   // aborted by either party
)

// Location is a geographic point reported by a device, with the bearing the
// device was moving and the moment it was observed.
type Location struct {
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	Heading   float64   `json:"heading"` // bearing in degrees clockwise from North
	UpdatedAt time.Time `json:"updatedAt"`
}

// Driver is a registered driver together with their live state. The persistent
// fields (ID, PhoneE164, Name, Vehicle, CreatedAt) come from PostgreSQL; Status
// and Location are the real-time fields held in memstore and never trusted from
// the database.
type Driver struct {
	ID        string       `json:"id"`
	PhoneE164 string       `json:"phoneE164"`
	Name      string       `json:"name"`
	Vehicle   string       `json:"vehicle"`
	CreatedAt time.Time    `json:"createdAt"`
	Status    DriverStatus `json:"status"`
	Location  Location     `json:"location"`
}

// DriverTransmission is which gearbox(es) a driver can drive. Collected on the
// driver app's "Type of Vehicle" step; matchmaking uses it to respect the
// customer's [CarTransmission].
type DriverTransmission string

const (
	DriverTransmissionManual    DriverTransmission = "manual"
	DriverTransmissionAutomatic DriverTransmission = "automatic"
	DriverTransmissionBoth      DriverTransmission = "both"
)

// Gender is the driver's gender, collected on the Photo and Name step.
type Gender string

const (
	GenderMale   Gender = "male"
	GenderFemale Gender = "female"
	GenderOther  Gender = "other"
)

// DocumentKind names one of the KYC images a driver uploads.
type DocumentKind string

const (
	DocumentSelfie         DocumentKind = "selfie"
	DocumentAadhaar        DocumentKind = "aadhaar"
	DocumentDrivingLicense DocumentKind = "driving_license"
)

// DocumentKinds lists every kind a driver must supply, in the order the app's
// Document View asks for them.
var DocumentKinds = []DocumentKind{
	DocumentSelfie,
	DocumentAadhaar,
	DocumentDrivingLicense,
}

// DocumentStatus is where one uploaded image sits in review.
type DocumentStatus string

const (
	DocumentPending  DocumentStatus = "pending"  // uploaded, awaiting review
	DocumentVerified DocumentStatus = "verified" // accepted by a reviewer
	DocumentRejected DocumentStatus = "rejected" // needs re-uploading
)

// KYCStatus is the driver's overall onboarding state. Owned by the server —
// the app reports what it collected, never whether it passed.
type KYCStatus string

const (
	KYCIncomplete KYCStatus = "incomplete" // still filling in the Document View
	KYCSubmitted  KYCStatus = "submitted"  // everything supplied, awaiting review
	KYCVerified   KYCStatus = "verified"   // cleared to drive
	KYCRejected   KYCStatus = "rejected"   // something was refused
)

// DriverDocument is one uploaded KYC image. The bytes live in object storage
// (see internal/storage); PostgreSQL holds this metadata and the key that
// finds them. ObjectKey never leaves the server — clients read an image
// through the documents endpoint, which checks the session first.
type DriverDocument struct {
	ID           string         `json:"id"`
	Kind         DocumentKind   `json:"kind"`
	ObjectKey    string         `json:"-"`
	ContentType  string         `json:"contentType"`
	ByteSize     int64          `json:"byteSize"`
	SHA256       string         `json:"sha256"`
	Status       DocumentStatus `json:"status"`
	RejectReason string         `json:"rejectReason,omitempty"`
	UploadedAt   time.Time      `json:"uploadedAt"`
	ReviewedAt   *time.Time     `json:"reviewedAt,omitempty"`
}

// DriverProfile is the typed, non-image half of a driver's KYC. AadhaarLast4
// is all that is kept of the Aadhaar number — see the secret package for why.
type DriverProfile struct {
	FullName             string             `json:"fullName"`
	DateOfBirth          *time.Time         `json:"dateOfBirth,omitempty"`
	Gender               Gender             `json:"gender,omitempty"`
	Transmission         DriverTransmission `json:"transmission,omitempty"`
	AadhaarLast4         string             `json:"aadhaarLast4,omitempty"`
	DrivingLicenseNumber string             `json:"drivingLicenseNumber,omitempty"`
	KYCStatus            KYCStatus          `json:"kycStatus"`
	KYCSubmittedAt       *time.Time         `json:"kycSubmittedAt,omitempty"`
}

// DriverBankAccount is where a driver's earnings are paid. The account number
// is encrypted at rest and never returned to a client; Last4 is what the app
// shows so the driver can recognise their own account.
type DriverBankAccount struct {
	AccountHolderName string    `json:"accountHolderName"`
	AccountNumberLast4 string   `json:"accountNumberLast4"`
	IFSCCode          string    `json:"ifscCode"`
	UpdatedAt         time.Time `json:"updatedAt"`
}

// DriverKYC is the whole Document View as the app needs to render it: what has
// been collected, what has been uploaded, and where review stands.
type DriverKYC struct {
	Profile     DriverProfile      `json:"profile"`
	Documents   []DriverDocument   `json:"documents"`
	BankAccount *DriverBankAccount `json:"bankAccount,omitempty"`
}

// RecentPickup is a place a customer has used as a ride pickup, kept as a short
// per-user history so the apps can offer it without a maps lookup. PostgreSQL is
// the source of truth; each app mirrors it into on-device storage as an offline
// cache. PlaceID is the map provider's opaque id (empty for a GPS-only point).
type RecentPickup struct {
	PlaceID string    `json:"placeId,omitempty"`
	Address string    `json:"address"`
	Lat     float64   `json:"lat"`
	Lng     float64   `json:"lng"`
	UsedAt  time.Time `json:"usedAt"`
}

// CarType is the class of car a customer can register and book with.
type CarType string

const (
	CarTypeHatchback CarType = "hatchback"
	CarTypeSedan     CarType = "sedan"
	CarTypeSUV       CarType = "suv"
	CarTypeLuxury    CarType = "luxury"
)

// CarTransmission is the gearbox of a customer's car, which decides what a
// driver must be able to drive.
type CarTransmission string

const (
	TransmissionAutomatic CarTransmission = "automatic"
	TransmissionManual    CarTransmission = "manual"
)

// Car is a customer's saved car. Sarthi drivers drive the customer's own car,
// so a booking picks one of these instead of re-describing the car each trip.
// PostgreSQL is the source of truth. Registration is the normalised plate
// (uppercase, separators stripped, e.g. "KA01AB1234").
type Car struct {
	ID           string          `json:"id"`
	Registration string          `json:"registration"`
	CarType      CarType         `json:"carType"`
	Transmission CarTransmission `json:"transmission"`
	CreatedAt    time.Time       `json:"createdAt"`
}

// Booking is a confirmed trip request submitted from the customer app. Until
// matchmaking and the ride pipeline exist, PostgreSQL is the source of truth
// for what the customer asked for. TripType is "roundTrip", "oneWay" or
// "multiStop"; Details is the schemaless per-trip-type payload the app sent,
// persisted verbatim as JSONB so the pipeline can be designed against real
// bookings.
type Booking struct {
	ID        string         `json:"id"`
	UserID    string         `json:"userId"`
	TripType  string         `json:"tripType"`
	Details   map[string]any `json:"details"`
	CreatedAt time.Time      `json:"createdAt"`
}

// Ride is a single trip request and its full lifecycle. Completed rides are the
// source of truth for financials, so monetary amounts are stored as integer
// minor units (cents) to avoid floating-point drift.
type Ride struct {
	ID          string     `json:"id"`
	RiderID     string     `json:"riderId"`
	DriverID    string     `json:"driverId,omitempty"`
	Status      RideStatus `json:"status"`
	Pickup      Location   `json:"pickup"`
	Dropoff     Location   `json:"dropoff"`
	FareCents   int64      `json:"fareCents"`
	RequestedAt time.Time  `json:"requestedAt"`
	CompletedAt *time.Time `json:"completedAt,omitempty"`
}
