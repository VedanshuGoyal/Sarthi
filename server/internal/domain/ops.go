package domain

import "time"

// SettleMode is how MOJUD closed a completed ride's bill by hand, without
// the payment gateway.
type SettleMode string

const (
	// SettledCash: the customer paid the driver directly. MOJUD received
	// nothing, takes no commission on it, and owes the driver nothing.
	SettledCash SettleMode = "cash"
	// SettledWaived: nobody pays — a goodwill or disputed ride. The driver is
	// not paid for it either.
	SettledWaived SettleMode = "waived"
)

// Valid reports whether m is a mode the back office may settle with.
func (m SettleMode) Valid() bool { return m == SettledCash || m == SettledWaived }

// BookingPayment is how a paid ride was paid, for the customer's receipt.
// Mode is the gateway's payment mode verbatim (UPI_INTENT, UPI_QR, …), or
// CASH / WAIVED for a ride MOJUD settled by hand; UTR, TransactionID and
// MerchantOrderID are the references a dispute needs, when there are any.
type BookingPayment struct {
	Mode            string    `json:"mode"`
	UTR             string    `json:"utr,omitempty"`
	TransactionID   string    `json:"transactionId,omitempty"`
	MerchantOrderID string    `json:"merchantOrderId,omitempty"`
	PaidAt          time.Time `json:"paidAt"`
}

// FareBreakdown splits a round trip's fare into the hourly tariff and the
// late-night surcharge. Both in paise.
type FareBreakdown struct {
	BasePaise  int64 `json:"basePaise"`
	NightPaise int64 `json:"nightPaise"`
}

// AdminAction is one back-office change, as the audit trail keeps it.
type AdminAction struct {
	ID      int64          `json:"id"`
	Actor   string         `json:"actor"`
	Action  string         `json:"action"`
	Target  string         `json:"target"`
	Details map[string]any `json:"details,omitempty"`
	At      time.Time      `json:"at"`
}

// Audit trail actions.
const (
	ActionBookingAssign = "booking.assign"
	ActionBookingCancel = "booking.cancel"
	ActionBookingSettle = "booking.settle"
	ActionKYCDecide     = "kyc.decide"
	ActionPayoutRecord  = "payout.record"
)

// CancelledByOps is the cancelled_by of a ride MOJUD cancelled from the back
// office.
const CancelledByOps = "ops"

// AdminParty is the customer or driver on a booking, as ops see them.
type AdminParty struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
}

// AdminBookingRow is a booking with its customer and driver and how it was
// paid, as the repository reads it for the back office.
type AdminBookingRow struct {
	Booking  Booking
	Customer AdminParty
	Driver   *AdminParty
	// PaidMode is "cash" or "waived" for a ride settled by hand, "" for a
	// gateway payment or an unpaid ride.
	PaidMode string
	PaidNote string
}

// AdminBooking is a booking as the back office lists it.
type AdminBooking struct {
	ID            string            `json:"id"`
	TripType      string            `json:"tripType"`
	Status        RideStatus        `json:"status"`
	ScheduledAt   time.Time         `json:"scheduledAt"`
	CreatedAt     time.Time         `json:"createdAt"`
	FarePaise     int64             `json:"farePaise"`
	FareEstimated bool              `json:"fareEstimated"`
	Pickup        string            `json:"pickup"`
	Destination   string            `json:"destination,omitempty"`
	Car           *RideCar          `json:"car,omitempty"`
	Customer      AdminParty        `json:"customer"`
	Driver        *AdminParty       `json:"driver,omitempty"`
	AcceptedAt    *time.Time        `json:"acceptedAt,omitempty"`
	StartedAt     *time.Time        `json:"startedAt,omitempty"`
	CompletedAt   *time.Time        `json:"completedAt,omitempty"`
	CancelledAt   *time.Time        `json:"cancelledAt,omitempty"`
	CancelledBy   string            `json:"cancelledBy,omitempty"`
	CancelReason  string            `json:"cancelReason,omitempty"`
	PaymentStatus RidePaymentStatus `json:"paymentStatus,omitempty"`
	PaidAt        *time.Time        `json:"paidAt,omitempty"`
	PaidMode      string            `json:"paidMode,omitempty"`
	PaidNote      string            `json:"paidNote,omitempty"`
	PaidPaise     int64             `json:"paidPaise,omitempty"`
	PayoutID      string            `json:"payoutId,omitempty"`
}

// AttentionOrder is a payment order someone at MOJUD has to look at.
type AttentionOrder struct {
	MerchantOrderID string       `json:"merchantOrderId"`
	BookingID       string       `json:"bookingId"`
	UserID          string       `json:"userId"`
	AmountPaise     int64        `json:"amountPaise"`
	State           PaymentState `json:"state"`
	TransactionID   string       `json:"transactionId,omitempty"`
	PaymentMode     string       `json:"paymentMode,omitempty"`
	UTR             string       `json:"utr,omitempty"`
	CreatedAt       time.Time    `json:"createdAt"`
	UpdatedAt       time.Time    `json:"updatedAt"`
	// PaidBy is what the booking was actually paid by: another order's
	// merchant order id, or "cash" / "waived" for a ride settled by hand.
	PaidBy string `json:"paidBy,omitempty"`
}

// PaymentAttention is the back office's money to-do list: completed orders
// for rides another order (or a hand settlement) had already paid — a
// refund owed — and orders still pending long after the sweep gave up on
// them.
type PaymentAttention struct {
	PaidTwice    []AttentionOrder `json:"paidTwice"`
	StalePending []AttentionOrder `json:"stalePending"`
}
