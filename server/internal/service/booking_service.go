package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// ErrInvalidBooking is returned when a submitted booking names no trip type or
// carries no details.
var ErrInvalidBooking = errors.New("booking tripType and details are required")

// ErrCannotCancel is returned when a customer cancels a ride that has
// already started, ended or been cancelled.
var ErrCannotCancel = fmt.Errorf("this ride has already started or ended, so it can't be cancelled: %w",
	repository.ErrBookingStateConflict)

// ErrCannotEnd is returned when a customer ends a trip that isn't in
// progress.
var ErrCannotEnd = fmt.Errorf("this trip isn't in progress, so it can't be ended: %w",
	repository.ErrBookingStateConflict)

// CancellationFeeError refuses a cancellation that costs more than the
// customer agreed to — the driver reached the pickup after the app showed
// a free cancel. Nothing changed; FeePaise is what cancelling costs now.
type CancellationFeeError struct{ FeePaise int64 }

func (e *CancellationFeeError) Error() string {
	return "Your driver has reached the pickup, so cancelling now costs " + formatFare(e.FeePaise, false) + "."
}

// ErrCannotRate is returned when a customer rates a ride that isn't
// completed, or rates it twice.
var ErrCannotRate = fmt.Errorf("you can rate a ride once, after it's completed: %w",
	repository.ErrBookingStateConflict)

// ErrCarRequired is returned when a booking from an app that asks for the
// customer's car on every trip type names none, or a car it can't read.
var ErrCarRequired = errors.New("choose the car the driver will drive")

// ErrBookingTooSoon is returned when a booking starts too soon for a driver
// to accept it before it closes (see acceptCutoff).
var ErrBookingTooSoon = errors.New("pick a start time at least 45 minutes from now")

const (
	// acceptCutoff is how long before its start an open ride stops taking
	// drivers — the time a driver needs to reach the pickup. A ride nobody
	// took by then is reported to the customer as expired.
	acceptCutoff = 30 * time.Minute

	// minBookingLead is how far ahead a ride must be booked: the cutoff plus
	// a quarter hour for a driver to accept. The app offers no earlier slot.
	minBookingLead = 45 * time.Minute

	// bookingLeadSlack forgives the minutes a customer spends on the form
	// after picking the earliest slot.
	bookingLeadSlack = 5 * time.Minute

	// maxCancelReason caps the reason a customer gives for cancelling, in
	// characters; a longer one is cut.
	maxCancelReason = 200

	// duplicateWindow is how long a submit identical to an earlier one (same
	// trip type, start and details) is taken as a retry of it rather than a
	// second booking — for apps that send no idempotency key.
	duplicateWindow = 10 * time.Minute

	// maxIdempotencyKey caps the app's Idempotency-Key, in bytes.
	maxIdempotencyKey = 100
)

// closedToDrivers reports whether an open ride starting at start can no
// longer be accepted at now.
func closedToDrivers(start, now time.Time) bool {
	return now.After(start.Add(-acceptCutoff))
}

// BookingStore is the slice of persistence this service needs. Defined
// consumer-side so the service stays testable with a fake.
type BookingStore interface {
	Insert(ctx context.Context, p repository.InsertBookingParams) (b domain.Booking, existing bool, err error)
	UnpaidDues(ctx context.Context, userID string) ([]domain.Due, error)
	ListForUser(ctx context.Context, userID string, limit int) ([]domain.UserBooking, error)
	FindForUser(ctx context.Context, id, userID string) (domain.UserBooking, error)
	PaymentLines(ctx context.Context, userID string, merchantOrderIDs []string) (map[string][]domain.PaymentLine, error)
	Cancel(ctx context.Context, id, userID, reason string, at time.Time, atPickup repository.PickupCancel) (domain.Booking, error)
	EndEarly(ctx context.Context, id, userID string, farePaise int64, at time.Time) (domain.Booking, error)
	RateDriver(ctx context.Context, id, userID string, rating domain.RideRating) error
	DriverBusyElsewhere(ctx context.Context, driverID, bookingID string) (bool, error)
}

// BookingAlerter tells drivers about bookings (NotifyService): a new ride
// request goes to those nearby, a cancelled ride to the driver who had it.
// Each call returns at once; the alerts go out in the background.
type BookingAlerter interface {
	RideRequested(ctx context.Context, b domain.Booking, plan tripPlan)
	RideCancelled(ctx context.Context, b domain.Booking, plan tripPlan)
	RideEndedEarly(ctx context.Context, b domain.Booking, plan tripPlan)
}

// DriverLocator reads the positions drivers' apps share while on a ride
// (memstore.LiveLocations).
type DriverLocator interface {
	Latest(driverID string) (domain.LiveLocation, bool)
}

// DriverPhotos serves the small copy of a driver's selfie that customers see
// (DriverKYCService).
type DriverPhotos interface {
	OpenDriverPhoto(ctx context.Context, driverID string) ([]byte, string, error)
}

// maxCustomerBookings caps the customer's bookings list.
const maxCustomerBookings = 50

// BookingService runs the customer side of a booking's life: recording it,
// listing it with its driver and progress, cancelling it before the trip
// starts, rating the driver afterwards, and showing where the driver is
// while they're on the way.
//
// A recorded booking is an open ride request: drivers see it in their app's
// requests feed (see DriverRideService) until one accepts it. PostgreSQL is
// the source of truth.
type BookingService struct {
	store  BookingStore
	alerts BookingAlerter
	live   DriverLocator
	photos DriverPhotos
	// paymentsOff: no gateway is configured, so nothing can be paid in the
	// app and an unpaid ride can't hold up a new booking.
	paymentsOff bool
	now         func() time.Time
}

// NewBookingService wires the service to its store, the driver alerts sent
// for new and cancelled bookings (nil sends none), the drivers' shared
// positions (nil shows none) and their photos (nil shows none).
func NewBookingService(store BookingStore, alerts BookingAlerter, live DriverLocator, photos DriverPhotos) *BookingService {
	return &BookingService{store: store, alerts: alerts, live: live, photos: photos, now: time.Now}
}

// SetPaymentsEnabled says whether a payment gateway is configured (on by
// default). With payments off, Record skips the unpaid-ride check: the
// customer would have no way to pay.
func (s *BookingService) SetPaymentsEnabled(on bool) { s.paymentsOff = !on }

// Record validates and persists userID's confirmed booking of the given
// tripType ("roundTrip", "oneWay", "multiStop"), returning the stored booking
// with the id the database assigned.
//
// requireCar is set for apps that ask for the customer's car on every trip
// type (the user app from build 10): such a booking must name a complete
// car, or it is refused with [ErrCarRequired]. Older builds book
// multi-stop trips without a car, and any driver may take those.
//
// A customer with a ride or fee still to pay for may book: what they owe
// is collected with their next payment (see [PaymentService.Checkout]). A
// repeat of a booking already made —
// the same idempotencyKey (the app's, per booking attempt; "" for none), or
// the same trip type, start and details within duplicateWindow — returns
// that booking with duplicate true, and no driver is alerted again.
func (s *BookingService) Record(
	ctx context.Context, userID, tripType string, details map[string]any, idempotencyKey string, requireCar bool,
) (b domain.Booking, duplicate bool, err error) {
	tripType, idempotencyKey = strings.TrimSpace(tripType), strings.TrimSpace(idempotencyKey)
	if tripType == "" || len(details) == 0 {
		return domain.Booking{}, false, ErrInvalidBooking
	}
	if len(idempotencyKey) > maxIdempotencyKey {
		return domain.Booking{}, false, fmt.Errorf("%w: Idempotency-Key is longer than %d characters",
			ErrInvalidBooking, maxIdempotencyKey)
	}
	// Read the details now rather than when a driver lists them: a booking no
	// driver can read is one nobody will ever take.
	plan, err := parseTripPlan(tripType, details)
	if err != nil {
		return domain.Booking{}, false, fmt.Errorf("%w: %v", ErrInvalidBooking, err)
	}
	if requireCar && !completeCar(plan.Car) {
		slog.WarnContext(ctx, "booking refused: no car", "userId", userID, "tripType", tripType)
		return domain.Booking{}, false, ErrCarRequired
	}
	now := s.now()
	if plan.ScheduledAt.Before(now.Add(minBookingLead - bookingLeadSlack)) {
		return domain.Booking{}, false, ErrBookingTooSoon
	}
	// The fare is the server's, not the client's: a tampered quote or drive
	// time is refused rather than silently repriced.
	if err := plan.checkBookable(tripType); err != nil {
		slog.WarnContext(ctx, "booking refused: price check", "userId", userID, "tripType", tripType, "error", err)
		return domain.Booking{}, false, err
	}
	fare, estimated := plan.Fare()
	booking, existing, err := s.store.Insert(ctx, repository.InsertBookingParams{
		UserID:         userID,
		TripType:       tripType,
		Details:        details,
		ScheduledAt:    plan.ScheduledAt,
		FarePaise:      fare,
		FareEstimated:  estimated,
		IdempotencyKey: idempotencyKey,
		DuplicateSince: now.Add(-duplicateWindow),
	})
	if err != nil {
		return domain.Booking{}, false, err
	}
	if existing {
		slog.InfoContext(ctx, "booking repeated; returning the first",
			"bookingId", booking.ID, "userId", userID, "tripType", tripType, "byKey", idempotencyKey != "")
		return booking, true, nil
	}
	slog.InfoContext(ctx, "booking confirmed",
		"bookingId", booking.ID,
		"userId", userID,
		"tripType", tripType,
	)
	if s.alerts != nil {
		s.alerts.RideRequested(ctx, booking, plan)
	}
	return booking, false, nil
}

// ListMine returns userID's bookings, latest scheduled first, each with its
// status, assigned driver and — while the driver is on the way or waiting at
// the pickup — the code the customer gives them to start the trip. A paid
// booking's receipt lists every booking its payment paid. A request
// no driver took before it closed is reported as expired. A booking whose
// details can't be read is skipped rather than failing the list.
func (s *BookingService) ListMine(ctx context.Context, userID string) ([]domain.CustomerBooking, error) {
	rows, err := s.store.ListForUser(ctx, userID, maxCustomerBookings)
	if err != nil {
		return nil, err
	}
	owed, err := s.owed(ctx, userID)
	if err != nil {
		return nil, err
	}
	now := s.now()
	out := []domain.CustomerBooking{}
	for _, ub := range rows {
		if cb, ok := toCustomerBooking(ctx, ub, now, s.pickupFee()); ok {
			out = append(out, withCarried(cb, owed))
		}
	}
	return s.withPaymentLines(ctx, userID, out), nil
}

// owed is what userID still owes for, by booking id — nothing while
// payments are off, since none of it could be paid.
func (s *BookingService) owed(ctx context.Context, userID string) (map[string]int64, error) {
	if s.paymentsOff {
		return nil, nil
	}
	dues, err := s.store.UnpaidDues(ctx, userID)
	if err != nil {
		return nil, err
	}
	owed := make(map[string]int64, len(dues))
	for _, d := range dues {
		owed[d.BookingID] = d.AmountPaise
	}
	return owed, nil
}

// withCarried sets cb.CarriedPaise: what the customer owes on their other
// bookings, collected with this one's payment — on a booking still to be
// paid, either due now or underway. owed is every unpaid due by booking.
func withCarried(cb domain.CustomerBooking, owed map[string]int64) domain.CustomerBooking {
	switch {
	case cb.PaymentStatus == domain.RidePaymentDue:
	case cb.PaymentStatus == "" && (cb.Status == domain.RideStatusRequested || cb.Status == domain.RideStatusAccepted ||
		cb.Status == domain.RideStatusArrived || cb.Status == domain.RideStatusInProgress):
	default:
		return cb
	}
	for id, amount := range owed {
		if id != cb.ID {
			cb.CarriedPaise += amount
		}
	}
	return cb
}

// Cancel cancels userID's booking before the trip starts. It is free until
// the driver reaches the pickup; after that it costs
// [domain.CancellationFeePaise], paid like a ride. acceptFeePaise is the fee
// the app showed the customer: a cancel that would cost more is refused
// with [*CancellationFeeError] so the app can ask again. Apps from before
// the fee send none (nil) and cancel free.
func (s *BookingService) Cancel(ctx context.Context, userID, bookingID, reason string, acceptFeePaise *int64) (domain.CustomerBooking, error) {
	reason = strings.TrimSpace(reason)
	if r := []rune(reason); len(r) > maxCancelReason {
		reason = strings.TrimSpace(string(r[:maxCancelReason]))
	}
	fee := s.pickupFee()
	atPickup := repository.PickupCancel{Allowed: true}
	if acceptFeePaise != nil {
		atPickup = repository.PickupCancel{Allowed: *acceptFeePaise >= fee, FeePaise: fee}
	}
	b, err := s.store.Cancel(ctx, bookingID, userID, reason, s.now(), atPickup)
	if errors.Is(err, repository.ErrBookingStateConflict) {
		if !atPickup.Allowed {
			if ub, ferr := s.store.FindForUser(ctx, bookingID, userID); ferr == nil &&
				ub.Booking.Status == domain.RideStatusArrived {
				return domain.CustomerBooking{}, &CancellationFeeError{FeePaise: fee}
			}
		}
		return domain.CustomerBooking{}, ErrCannotCancel
	}
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	slog.InfoContext(ctx, "booking cancelled by customer",
		"bookingId", b.ID, "userId", userID, "driverId", b.DriverID, "feePaise", b.CancellationFeePaise)
	if b.DriverID != "" && s.alerts != nil {
		if plan, err := planOf(b); err == nil {
			s.alerts.RideCancelled(ctx, b, plan)
		}
	}
	return s.mine(ctx, userID, bookingID)
}

// pickupFee is what cancelling at the pickup costs: nothing while payments
// are off, since it couldn't be paid.
func (s *BookingService) pickupFee() int64 {
	if s.paymentsOff {
		return 0
	}
	return domain.CancellationFeePaise
}

// EndEarly ends userID's trip in progress now, on the customer's say. They
// pay for the time used on the hourly tariff (see [finalFare]): never more
// than booked unless the trip already ran past its booked hours. The
// driver is told.
func (s *BookingService) EndEarly(ctx context.Context, userID, bookingID string) (domain.CustomerBooking, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	b := ub.Booking
	if b.Status != domain.RideStatusInProgress || b.StartedAt == nil {
		return domain.CustomerBooking{}, ErrCannotEnd
	}
	plan, err := planOf(b)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	booked := b.FarePaise
	if booked == 0 {
		booked, _ = plan.Fare()
	}
	now := s.now()
	fare := finalFare(plan, booked, *b.StartedAt, now, true)
	ended, err := s.store.EndEarly(ctx, b.ID, userID, fare, now)
	if errors.Is(err, repository.ErrBookingStateConflict) {
		return domain.CustomerBooking{}, ErrCannotEnd
	}
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	slog.InfoContext(ctx, "trip ended early by customer", "bookingId", b.ID, "userId", userID,
		"driverId", b.DriverID, "minutes", int(now.Sub(*b.StartedAt)/time.Minute),
		"farePaise", fare, "bookedFarePaise", booked)
	if s.alerts != nil {
		s.alerts.RideEndedEarly(ctx, ended, plan)
	}
	return s.mine(ctx, userID, bookingID)
}

// RateDriver records the stars userID gives the driver of their completed
// booking, once.
func (s *BookingService) RateDriver(ctx context.Context, userID, bookingID string, stars int, note string) (domain.CustomerBooking, error) {
	rating, err := newRating(stars, note)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	err = s.store.RateDriver(ctx, bookingID, userID, rating)
	if errors.Is(err, repository.ErrBookingStateConflict) {
		return domain.CustomerBooking{}, ErrCannotRate
	}
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	slog.InfoContext(ctx, "driver rated", "bookingId", bookingID, "userId", userID, "stars", stars)
	return s.mine(ctx, userID, bookingID)
}

// DriverPhoto returns the photo of the driver assigned to userID's booking,
// and its version (see [domain.RideDriver.PhotoVersion]). [ErrNoDriverPhoto]
// when no driver has accepted it or they have no photo.
func (s *BookingService) DriverPhoto(ctx context.Context, userID, bookingID string) ([]byte, string, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return nil, "", err
	}
	if ub.Booking.DriverID == "" || s.photos == nil {
		return nil, "", ErrNoDriverPhoto
	}
	return s.photos.OpenDriverPhoto(ctx, ub.Booking.DriverID)
}

// DriverLocation returns where the driver of userID's booking last said they
// were, while the ride is in its live-tracking window (see sharesLocation) —
// nil if they haven't shared a position within liveFixMaxAge, or while they
// are at or on another customer's ride: the position is the driver's, not
// this ride's, and that trip is someone else's business.
// [ErrNotTracking] outside the window.
func (s *BookingService) DriverLocation(ctx context.Context, userID, bookingID string) (*domain.LiveLocation, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return nil, err
	}
	b := ub.Booking
	plan, err := planOf(b)
	now := s.now()
	if err != nil || b.DriverID == "" || !sharesLocation(b.Status, plan.ScheduledAt, plan.EndsAt(), now) {
		return nil, ErrNotTracking
	}
	if s.live == nil {
		return nil, nil
	}
	busy, err := s.store.DriverBusyElsewhere(ctx, b.DriverID, b.ID)
	if err != nil {
		return nil, err
	}
	if busy {
		return nil, nil
	}
	loc, ok := s.live.Latest(b.DriverID)
	if !ok || now.Sub(loc.UpdatedAt) > liveFixMaxAge {
		return nil, nil
	}
	return &loc, nil
}

// Get returns one of userID's bookings as the customer app shows it.
func (s *BookingService) Get(ctx context.Context, userID, bookingID string) (domain.CustomerBooking, error) {
	return s.mine(ctx, userID, bookingID)
}

// mine re-reads one of userID's bookings as the customer app shows it.
func (s *BookingService) mine(ctx context.Context, userID, bookingID string) (domain.CustomerBooking, error) {
	ub, err := s.store.FindForUser(ctx, bookingID, userID)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	cb, ok := toCustomerBooking(ctx, ub, s.now(), s.pickupFee())
	if !ok {
		return domain.CustomerBooking{}, fmt.Errorf("booking %s: unreadable details", bookingID)
	}
	owed, err := s.owed(ctx, userID)
	if err != nil {
		return domain.CustomerBooking{}, err
	}
	return s.withPaymentLines(ctx, userID, []domain.CustomerBooking{withCarried(cb, owed)})[0], nil
}

// planOf reads a stored booking's details, with the start time the server
// recorded taking precedence over the one in them.
func planOf(b domain.Booking) (tripPlan, error) {
	plan, err := parseTripPlan(b.TripType, b.Details)
	if err != nil {
		return tripPlan{}, err
	}
	if b.ScheduledAt != nil {
		plan.ScheduledAt = *b.ScheduledAt
	}
	return plan, nil
}

// driverContact is the driver of booking b as the customer sees them at
// now: their number goes once the ride has been over for contactLifetime.
func driverContact(d *domain.RideDriver, b domain.Booking, now time.Time) *domain.RideDriver {
	if d == nil || !contactExpired(b, now) {
		return d
	}
	hidden := *d
	hidden.PhoneE164 = ""
	return &hidden
}

// roundTripBreakdown splits a round trip's fare into the hourly tariff and
// the night surcharge, as the tariff prices it now — or nil when that no
// longer adds up to the fare it was booked at (an older tariff), rather
// than show a receipt whose lines don't sum.
func roundTripBreakdown(plan tripPlan, farePaise int64) *domain.FareBreakdown {
	if plan.Hours < 1 {
		return nil
	}
	base := int64(hourlyTariffRupees(plan.Hours, plan.luxury())) * 100
	night := int64(nightSurchargeRupees(plan.ScheduledAt, plan.Hours)) * 100
	if base+night != farePaise {
		return nil
	}
	return &domain.FareBreakdown{BasePaise: base, NightPaise: night}
}

// toCustomerBooking renders a stored booking for the customer app, with
// pickupFee what cancelling costs once the driver is at the pickup. ok is
// false for one whose details can't be read.
func toCustomerBooking(ctx context.Context, ub domain.UserBooking, now time.Time, pickupFee int64) (domain.CustomerBooking, bool) {
	b := ub.Booking
	plan, err := planOf(b)
	if err != nil {
		slog.WarnContext(ctx, "booking skipped: unreadable details", "bookingId", b.ID, "error", err)
		return domain.CustomerBooking{}, false
	}
	fare, estimated := b.FarePaise, b.FareEstimated
	if fare == 0 {
		fare, estimated = plan.Fare()
	}
	cb := domain.CustomerBooking{
		ID:               b.ID,
		TripType:         b.TripType,
		Status:           b.Status,
		ScheduledAt:      plan.ScheduledAt,
		EndsAt:           plan.EndsAt(),
		FarePaise:        fare,
		FareEstimated:    estimated,
		Pickup:           plan.Pickup,
		Destination:      plan.Destination,
		StopCount:        len(plan.Stops),
		Stops:            plan.Stops,
		Hours:            plan.Hours,
		EstimatedMinutes: plan.EstimatedMinutes,
		Car:              plan.Car,
		Driver:           driverContact(ub.Driver, b, now),
		CreatedAt:        b.CreatedAt,
		AcceptedAt:       b.AcceptedAt,
		ArrivedAt:        b.ArrivedAt,
		StartedAt:        b.StartedAt,
		CompletedAt:      b.CompletedAt,
		CancelledAt:      b.CancelledAt,
		CancelledBy:      b.CancelledBy,
		CancelReason:     b.CancelReason,
		MyRating:         b.DriverRating,
		PaidAt:           b.PaidAt,
		BookedFarePaise:  b.BookedFarePaise,
	}
	switch b.Status {
	case domain.RideStatusArrived:
		cb.CancellationFeePaise = pickupFee // what cancelling now costs
	case domain.RideStatusCancelled:
		cb.CancellationFeePaise = b.CancellationFeePaise
	}
	// Paid out is the driver's business; to the customer it's just paid.
	switch b.PaymentStatus() {
	case domain.RidePaymentDue:
		cb.PaymentStatus = domain.RidePaymentDue
	case domain.RidePaymentPaid, domain.RidePaymentPaidOut:
		cb.PaymentStatus = domain.RidePaymentPaid
		cb.Payment = ub.Payment
	}
	if b.TripType == TripRoundTrip {
		cb.FareBreakdown = roundTripBreakdown(plan, fare)
	}
	if b.Status == domain.RideStatusAccepted || b.Status == domain.RideStatusArrived {
		cb.StartOTP = b.StartOTP
	}
	if b.Status == domain.RideStatusRequested && closedToDrivers(plan.ScheduledAt, now) {
		cb.Status = domain.RideStatusExpired
	}
	return cb, true
}
