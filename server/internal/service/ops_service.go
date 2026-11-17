package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// ErrInvalidOpsRequest is returned when a back-office request is malformed:
// an unknown status or date, or an action without the reason it needs.
var ErrInvalidOpsRequest = errors.New("invalid request")

const (
	// maxAdminBookings caps the back office's bookings list.
	maxAdminBookings = 200

	// maxAttentionOrders caps each list of payment orders needing attention.
	maxAttentionOrders = 100

	// maxOpsReason caps the reason an operator gives, in characters.
	maxOpsReason = 300

	// maxOperatorName caps the name an operator gives the admin page.
	maxOperatorName = 60
)

// Operator is who did something from the back office: the name they gave
// the admin page ("admin" when none — the token is shared) and where from.
type Operator struct {
	Name string
	IP   string
}

// OpsBookingStore is the back office's slice of bookings
// (repository.BookingRepository).
type OpsBookingStore interface {
	ListForAdmin(ctx context.Context, f repository.AdminBookingFilter) ([]domain.AdminBookingRow, error)
	FindForAdmin(ctx context.Context, id string) (domain.AdminBookingRow, error)
	CancelByOps(ctx context.Context, id, reason string, at time.Time) (domain.Booking, error)
}

// OpsRideStore is what assigning a driver needs from the ride lifecycle
// (repository.DriverRideRepository): the same conditional accept a driver's
// own tap runs.
type OpsRideStore interface {
	FindByID(ctx context.Context, id string) (domain.RideBooking, error)
	ListForDriver(ctx context.Context, driverID string, limit int) ([]domain.RideBooking, error)
	Accept(ctx context.Context, id, driverID string, at time.Time, startOTP string) (domain.RideBooking, error)
}

// OpsPaymentStore settles rides by hand and finds orders needing a person
// (repository.PaymentRepository).
type OpsPaymentStore interface {
	SettleByHand(ctx context.Context, id string, mode domain.SettleMode, note string, at time.Time) (domain.Booking, error)
	PaymentAttention(ctx context.Context, pendingBefore time.Time, limit int) (domain.PaymentAttention, error)
}

// AuditStore keeps the back office's audit trail
// (repository.AdminActionRepository).
type AuditStore interface {
	RecordAction(ctx context.Context, a domain.AdminAction) (domain.AdminAction, error)
	RecentActions(ctx context.Context, target string, limit int) ([]domain.AdminAction, error)
}

// OpsAlerter tells the people on a ride what the back office did to it
// (NotifyService). Each call returns at once.
type OpsAlerter interface {
	DriverAssigned(ctx context.Context, userID string, ride domain.DriverRide, driverName string)
	AssignedByOps(ctx context.Context, driverID string, ride domain.DriverRide)
	CancelledByOps(ctx context.Context, b domain.Booking, plan tripPlan)
}

// OpsCheckouts re-checks a booking's open UPI checkouts with the gateway
// ([PaymentService.SyncBooking]).
type OpsCheckouts interface {
	SyncBooking(ctx context.Context, bookingID string) error
}

// OpsDeps is what [NewOpsService] wires together. Alerts nil sends no
// pushes; Checkouts nil skips the gateway check before a settle.
type OpsDeps struct {
	Bookings  OpsBookingStore
	Rides     OpsRideStore
	Payments  OpsPaymentStore
	Checkouts OpsCheckouts
	Profiles  DriverProfileReader
	Audit     AuditStore
	Alerts    OpsAlerter
}

// OpsService is the back office's hands on bookings: list and filter them,
// give an open ride to a driver, cancel one, and close the bill of a ride
// paid outside the app — each written to the audit trail with who did it.
// It also lists the payment orders a person must look at.
type OpsService struct {
	d       OpsDeps
	now     func() time.Time
	newCode func() (string, error)
}

// NewOpsService wires the service.
func NewOpsService(d OpsDeps) *OpsService {
	return &OpsService{d: d, now: time.Now, newCode: newStartOTP}
}

// AdminBookingQuery is the bookings list's filter, as the admin page sends
// it: a status ("" any; "expired" and "unpaid" are derived), and a range of
// IST start dates, From to To inclusive, as YYYY-MM-DD ("" open-ended).
type AdminBookingQuery struct {
	Status   string
	From, To string
}

// Bookings lists the bookings q picks, latest start first, at most
// maxAdminBookings. A request no driver took before it closed reads as
// expired, as the customer sees it.
func (s *OpsService) Bookings(ctx context.Context, q AdminBookingQuery) ([]domain.AdminBooking, error) {
	now := s.now()
	f := repository.AdminBookingFilter{Limit: maxAdminBookings}
	var err error
	if f.ScheduledFrom, err = istDay(q.From, 0); err != nil {
		return nil, err
	}
	if f.ScheduledBefore, err = istDay(q.To, 1); err != nil {
		return nil, err
	}
	closes := now.Add(acceptCutoff) // a request starting before this is closed
	switch status := strings.TrimSpace(q.Status); status {
	case "":
	case "unpaid":
		f.Unpaid = true
	case string(domain.RideStatusRequested):
		f.Status = domain.RideStatusRequested
		f.ScheduledFrom = later(f.ScheduledFrom, closes)
	case string(domain.RideStatusExpired):
		f.Status = domain.RideStatusRequested
		f.ScheduledBefore = earlier(f.ScheduledBefore, closes)
	case string(domain.RideStatusAccepted), string(domain.RideStatusArrived), string(domain.RideStatusInProgress),
		string(domain.RideStatusCompleted), string(domain.RideStatusCancelled):
		f.Status = domain.RideStatus(status)
	default:
		return nil, fmt.Errorf("%w: unknown status %q", ErrInvalidOpsRequest, status)
	}
	rows, err := s.d.Bookings.ListForAdmin(ctx, f)
	if err != nil {
		return nil, err
	}
	out := make([]domain.AdminBooking, 0, len(rows))
	for _, row := range rows {
		out = append(out, toAdminBooking(row, now))
	}
	return out, nil
}

// Assign gives the open ride bookingID to driverID, as if they had accepted
// it — the same conditional accept, so a driver tapping it at that moment
// can't also win — except that it may be any time before the start, past
// the cutoff that closes a ride to drivers. The driver must still be cleared
// to drive, drive the car's gearbox and be free over its hours. The customer
// and the driver are told.
func (s *OpsService) Assign(ctx context.Context, op Operator, bookingID, driverID string) (domain.AdminBooking, error) {
	driverID = strings.TrimSpace(driverID)
	if !uuidPattern.MatchString(driverID) {
		return domain.AdminBooking{}, fmt.Errorf("%w: driverId must be a driver's id", ErrInvalidOpsRequest)
	}
	profile, err := s.d.Profiles.FindProfile(ctx, driverID)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	now := s.now()
	if err := clearedToDrive(profile, now); err != nil {
		return domain.AdminBooking{}, err
	}
	target, err := s.d.Rides.FindByID(ctx, bookingID)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	if target.Booking.Status != domain.RideStatusRequested {
		return domain.AdminBooking{}, repository.ErrRideUnavailable
	}
	_, plan, ok := toDriverRide(target, false)
	if !ok {
		return domain.AdminBooking{}, repository.ErrRideUnavailable
	}
	if !canDrive(profile.Transmission, plan.Car) {
		return domain.AdminBooking{}, ErrTransmissionMismatch
	}
	mine, err := s.d.Rides.ListForDriver(ctx, driverID, maxMyRides)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	for _, rb := range mine {
		if !holdsDriver(rb.Booking.Status) {
			continue
		}
		if _, other, ok := toDriverRide(rb, false); ok && overlaps(plan, other) {
			return domain.AdminBooking{}, fmt.Errorf("%w (ride %s)", ErrRideClash, rb.Booking.ID)
		}
	}
	code, err := s.newCode()
	if err != nil {
		return domain.AdminBooking{}, err
	}
	rb, err := s.d.Rides.Accept(ctx, bookingID, driverID, now, code)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	slog.InfoContext(ctx, "ops: ride assigned", "rideId", bookingID, "driverId", driverID, "by", op.Name)
	s.Audit(ctx, op, domain.ActionBookingAssign, bookingID, map[string]any{"driverId": driverID})
	if s.d.Alerts != nil {
		ride, _, _ := toDriverRide(rb, true)
		s.d.Alerts.DriverAssigned(ctx, rb.Booking.UserID, ride, profile.FullName)
		s.d.Alerts.AssignedByOps(ctx, driverID, ride)
	}
	return s.booking(ctx, bookingID)
}

// Cancel cancels bookingID for MOJUD at any step before it's completed,
// with the reason the operator must give; the customer and the driver who
// had it are told.
func (s *OpsService) Cancel(ctx context.Context, op Operator, bookingID, reason string) (domain.AdminBooking, error) {
	reason, err := opsReason(reason)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	b, err := s.d.Bookings.CancelByOps(ctx, bookingID, reason, s.now())
	if err != nil {
		return domain.AdminBooking{}, err
	}
	slog.InfoContext(ctx, "ops: ride cancelled", "rideId", b.ID, "driverId", b.DriverID, "by", op.Name)
	s.Audit(ctx, op, domain.ActionBookingCancel, b.ID, map[string]any{"reason": reason, "driverId": b.DriverID})
	if s.d.Alerts != nil {
		if plan, err := planOf(b); err == nil {
			s.d.Alerts.CancelledByOps(ctx, b, plan)
		}
	}
	return s.booking(ctx, bookingID)
}

// Settle closes the bill of completed, unpaid bookingID without the
// gateway (see [domain.SettleMode]), with the reason the operator must
// give. The customer can book again; the driver is owed nothing by MOJUD
// for it.
//
// The ride's UPI checkouts are re-checked with the gateway first, as
// Checkout does: one the customer paid meanwhile settles the ride for real,
// and one still open refuses the settle ([repository.ErrGatewayOrderOpen],
// a [repository.ErrBookingStateConflict]).
func (s *OpsService) Settle(ctx context.Context, op Operator, bookingID string, mode domain.SettleMode, reason string) (domain.AdminBooking, error) {
	if !mode.Valid() {
		return domain.AdminBooking{}, fmt.Errorf("%w: mode must be %q or %q", ErrInvalidOpsRequest,
			domain.SettledCash, domain.SettledWaived)
	}
	reason, err := opsReason(reason)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	if s.d.Checkouts != nil {
		// A failed check leaves the orders pending, which refuses below.
		if err := s.d.Checkouts.SyncBooking(ctx, bookingID); err != nil {
			slog.WarnContext(ctx, "ops: settle could not re-check the ride's checkouts", "rideId", bookingID, "error", err)
		}
	}
	b, err := s.d.Payments.SettleByHand(ctx, bookingID, mode, reason, s.now())
	if err != nil {
		return domain.AdminBooking{}, err
	}
	slog.InfoContext(ctx, "ops: ride settled by hand", "rideId", b.ID, "mode", mode, "farePaise", b.FarePaise, "by", op.Name)
	s.Audit(ctx, op, domain.ActionBookingSettle, b.ID, map[string]any{
		"mode": string(mode), "reason": reason, "farePaise": b.FarePaise, "driverId": b.DriverID,
	})
	return s.booking(ctx, bookingID)
}

// PaymentAttention lists the payment orders a person must look at: a ride
// paid twice (refund one by hand) and orders still pending after the
// sweep's window.
func (s *OpsService) PaymentAttention(ctx context.Context) (domain.PaymentAttention, error) {
	a, err := s.d.Payments.PaymentAttention(ctx, s.now().Add(-sweepWindow), maxAttentionOrders)
	if err != nil {
		return domain.PaymentAttention{}, err
	}
	if a.PaidTwice == nil {
		a.PaidTwice = []domain.AttentionOrder{}
	}
	if a.StalePending == nil {
		a.StalePending = []domain.AttentionOrder{}
	}
	return a, nil
}

// Audit appends one back-office change to the trail. The change has already
// happened, so a failure to write it is logged with everything it held
// rather than returned.
func (s *OpsService) Audit(ctx context.Context, op Operator, action, target string, details map[string]any) {
	if details == nil {
		details = map[string]any{}
	}
	if op.IP != "" {
		details["ip"] = op.IP
	}
	a := domain.AdminAction{Actor: OperatorName(op.Name), Action: action, Target: target, Details: details, At: s.now()}
	if _, err := s.d.Audit.RecordAction(ctx, a); err != nil {
		slog.ErrorContext(ctx, "ops: audit row not written", "error", err,
			"actor", a.Actor, "action", action, "target", target, "details", details)
	}
}

// RecentActions returns the latest limit audit rows, of target when set.
func (s *OpsService) RecentActions(ctx context.Context, target string, limit int) ([]domain.AdminAction, error) {
	return s.d.Audit.RecentActions(ctx, strings.TrimSpace(target), min(max(limit, 1), 200))
}

// OperatorName cleans the name an operator gave the admin page: trimmed,
// capped at maxOperatorName characters, "admin" when empty.
func OperatorName(name string) string {
	name = strings.Join(strings.Fields(name), " ")
	if r := []rune(name); len(r) > maxOperatorName {
		name = string(r[:maxOperatorName])
	}
	if name == "" {
		return "admin"
	}
	return name
}

// booking re-reads one booking for the back office after a change.
func (s *OpsService) booking(ctx context.Context, id string) (domain.AdminBooking, error) {
	row, err := s.d.Bookings.FindForAdmin(ctx, id)
	if err != nil {
		return domain.AdminBooking{}, err
	}
	return toAdminBooking(row, s.now()), nil
}

// toAdminBooking renders a booking for the back office. Unlike the apps'
// views it never skips one: unreadable details just leave the places blank.
func toAdminBooking(row domain.AdminBookingRow, now time.Time) domain.AdminBooking {
	b := row.Booking
	ab := domain.AdminBooking{
		ID:            b.ID,
		TripType:      b.TripType,
		Status:        b.Status,
		CreatedAt:     b.CreatedAt,
		FarePaise:     b.FarePaise,
		FareEstimated: b.FareEstimated,
		Customer:      row.Customer,
		Driver:        row.Driver,
		AcceptedAt:    b.AcceptedAt,
		StartedAt:     b.StartedAt,
		CompletedAt:   b.CompletedAt,
		CancelledAt:   b.CancelledAt,
		CancelledBy:   b.CancelledBy,
		CancelReason:  b.CancelReason,
		PaymentStatus: b.PaymentStatus(),
		PaidAt:        b.PaidAt,
		PaidMode:      row.PaidMode,
		PaidNote:      row.PaidNote,
		PaidPaise:     b.PaidPaise,
		PayoutID:      b.PayoutID,
	}
	if b.ScheduledAt != nil {
		ab.ScheduledAt = *b.ScheduledAt
	}
	if plan, err := planOf(b); err == nil {
		ab.ScheduledAt = plan.ScheduledAt
		ab.Pickup = plan.Pickup.Address
		if plan.Destination != nil {
			ab.Destination = plan.Destination.Address
		} else if n := len(plan.Stops); n > 0 {
			ab.Destination = plan.Stops[n-1].Place.Address
		}
		ab.Car = plan.Car
	}
	if b.Status == domain.RideStatusRequested && closedToDrivers(ab.ScheduledAt, now) {
		ab.Status = domain.RideStatusExpired
	}
	return ab
}

// opsReason trims and caps an operator's reason, which is required.
func opsReason(reason string) (string, error) {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		return "", fmt.Errorf("%w: give a reason", ErrInvalidOpsRequest)
	}
	if r := []rune(reason); len(r) > maxOpsReason {
		reason = strings.TrimSpace(string(r[:maxOpsReason]))
	}
	return reason, nil
}

// istDay is the start of the IST day date (YYYY-MM-DD) plus addDays, or the
// zero time for "".
func istDay(date string, addDays int) (time.Time, error) {
	date = strings.TrimSpace(date)
	if date == "" {
		return time.Time{}, nil
	}
	d, err := time.ParseInLocation(time.DateOnly, date, ist)
	if err != nil {
		return time.Time{}, fmt.Errorf("%w: dates are YYYY-MM-DD, not %q", ErrInvalidOpsRequest, date)
	}
	return d.AddDate(0, 0, addDays), nil
}

// later is the later of a and b, a zero time counting as unset.
func later(a, b time.Time) time.Time {
	if a.IsZero() || b.After(a) {
		return b
	}
	return a
}

// earlier is the earlier of a and b, a zero time counting as unset.
func earlier(a, b time.Time) time.Time {
	if a.IsZero() || b.Before(a) {
		return b
	}
	return a
}

// uuidPattern matches a UUID in its usual text form.
var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
