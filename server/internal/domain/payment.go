package domain

import "time"

// PaymentState is where one checkout (a payment order) stands. It only ever
// moves pending → completed | failed, and only on the gateway's word.
type PaymentState string

const (
	PaymentPending   PaymentState = "pending"
	PaymentCompleted PaymentState = "completed"
	PaymentFailed    PaymentState = "failed"
)

// PaymentOrder is one checkout the customer opened for a completed ride.
// MerchantOrderID is our name for it at the gateway; ProviderOrderID the
// gateway's own. Money is integer paise.
type PaymentOrder struct {
	MerchantOrderID string
	BookingID       string
	UserID          string
	AmountPaise     int64
	ProviderOrderID string
	// CheckoutToken is what the app's SDK opens the order with. It is
	// cleared once a new order replaces this one, so the open-order guard
	// stops counting it. Empty for orders opened before it was stored.
	CheckoutToken string
	State         PaymentState
	TransactionID string
	PaymentMode   string
	UTR           string
	ExpiresAt     time.Time
	CreatedAt     time.Time

	// Attempting says the gateway has a payment on this order under way:
	// the customer may be in their UPI app right now. Not stored; set by the
	// sync that asked.
	Attempting bool

	// Items are the bookings the order pays and each one's part of
	// AmountPaise: the booking tapped (BookingID) and any other the customer
	// still owes for, carried into this payment. Empty on an order read
	// back from the store; the store fills it in where it needs it.
	Items []PaymentItem
}

// PaymentItem is one booking a payment order pays, and how much of it.
type PaymentItem struct {
	BookingID   string
	AmountPaise int64
}

// Due is one thing a customer still owes for: an unpaid completed ride or
// cancellation fee.
type Due struct {
	BookingID   string
	AmountPaise int64
}

// SettleResult is what recording a completed order did: its outcome, the
// bookings this call marked paid, and the ids of bookings it covered that
// something else had paid first — money to refund by hand.
type SettleResult struct {
	Outcome     SettleOutcome
	Paid        []Booking
	AlreadyPaid []string
}

// SettleOutcome is what recording a completed order did to its bookings.
type SettleOutcome int

const (
	// SettledNow: the order completed and paid its bookings.
	SettledNow SettleOutcome = iota
	// SettledAlready: another call had already recorded this order.
	SettledAlready
	// SettledPaidTwice: the order completed, but something else had already
	// paid one or more of its bookings — money to refund by hand.
	SettledPaidTwice
)

// GatewayOrder is what the gateway hands back for a new order: its id and
// the token the customer app's checkout SDK opens it with.
type GatewayOrder struct {
	ProviderOrderID string
	Token           string
	ExpiresAt       time.Time
}

// GatewayOrderStatus is the gateway's account of an order: its state, the
// amount it was for, and — once paid — how (UPI_INTENT, UPI_QR, …) with the
// transaction ids a dispute would need.
type GatewayOrderStatus struct {
	State         PaymentState
	AmountPaise   int64
	TransactionID string
	PaymentMode   string
	UTR           string
	// Attempting: the order is still open and one of its payment attempts
	// hasn't failed, so money may yet move.
	Attempting bool
}

// PaymentCheckout is what the customer app needs to open the gateway's
// payment page for a ride: the gateway's order id and token, plus the
// merchant and environment its SDK is initialised with.
type PaymentCheckout struct {
	Provider        string    `json:"provider"`
	Environment     string    `json:"environment"`
	MerchantID      string    `json:"merchantId"`
	OrderID         string    `json:"orderId"`
	Token           string    `json:"token"`
	MerchantOrderID string    `json:"merchantOrderId"`
	AmountPaise     int64     `json:"amountPaise"`
	ExpiresAt       time.Time `json:"expiresAt"`
}

// RidePaymentStatus is where a completed ride's money is, as the apps show
// it. Empty until the ride is completed.
type RidePaymentStatus string

const (
	// RidePaymentDue: completed, the customer hasn't paid yet.
	RidePaymentDue RidePaymentStatus = "due"
	// RidePaymentPaid: the customer paid MOJUD; the driver's share is owed.
	RidePaymentPaid RidePaymentStatus = "paid"
	// RidePaymentPaidOut: the driver's share went out in a payout. Only the
	// driver app sees this; to the customer the ride is just paid.
	RidePaymentPaidOut RidePaymentStatus = "paid_out"
)

// DriverPaymentSummary is the money side of a driver's earnings panel: what
// customers still owe on their completed rides, what MOJUD owes the driver
// (customers paid, not yet transferred, after MOJUD's commission), and what
// has been transferred.
type DriverPaymentSummary struct {
	AwaitingCustomerPaise int64      `json:"awaitingCustomerPaise"`
	AwaitingCustomerRides int        `json:"awaitingCustomerRides"`
	DuePaise              int64      `json:"duePaise"`
	DueRides              int        `json:"dueRides"`
	PaidOutPaise          int64      `json:"paidOutPaise"`
	LastPayoutAt          *time.Time `json:"lastPayoutAt,omitempty"`
}

// PayoutDue is what MOJUD owes one driver right now — their share of every
// paid ride not yet paid out — with the bank details to send it to.
// AccountNumber is decrypted only for the admin payouts list.
//
// A driver who isn't KYC-verified, or whose account the bank hasn't
// confirmed, is OnHold: still owed, but listed without bank details until
// that's settled (HoldReason says why).
type PayoutDue struct {
	DriverID          string `json:"driverId"`
	DriverName        string `json:"driverName"`
	DriverPhone       string `json:"driverPhone"`
	Rides             int    `json:"rides"`
	AmountPaise       int64  `json:"amountPaise"`
	AccountHolderName string `json:"accountHolderName,omitempty"`
	AccountNumber     string `json:"accountNumber,omitempty"`
	IFSCCode          string `json:"ifscCode,omitempty"`
	// VerifiedName is the name the bank holds for the account (the penny
	// drop's), as opposed to the AccountHolderName the driver typed.
	VerifiedName string `json:"verifiedName,omitempty"`
	// AccountUpdatedAt is when the driver last changed the account.
	AccountUpdatedAt *time.Time `json:"accountUpdatedAt,omitempty"`

	OnHold     bool   `json:"onHold,omitempty"`
	HoldReason string `json:"holdReason,omitempty"`

	// AccountNumberEncrypted is how the store hands the number over; the
	// service opens it into AccountNumber.
	AccountNumberEncrypted []byte `json:"-"`
	// KYCStatus and AccountVerifiedAt decide the hold.
	KYCStatus         KYCStatus  `json:"-"`
	AccountVerifiedAt *time.Time `json:"-"`
}

// DriverPayout is one bank transfer to a driver covering Rides paid rides.
type DriverPayout struct {
	ID          string    `json:"id"`
	DriverID    string    `json:"driverId"`
	AmountPaise int64     `json:"amountPaise"`
	Rides       int       `json:"rides"`
	Reference   string    `json:"reference"`
	CreatedAt   time.Time `json:"createdAt"`
}
