package service

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// fakeOpsBookings serves the back office's booking reads from rows and
// records the filter it was asked with.
type fakeOpsBookings struct {
	rows      map[string]*domain.AdminBookingRow
	gotFilter repository.AdminBookingFilter
}

func (f *fakeOpsBookings) ListForAdmin(_ context.Context, flt repository.AdminBookingFilter) ([]domain.AdminBookingRow, error) {
	f.gotFilter = flt
	var out []domain.AdminBookingRow
	for _, r := range f.rows {
		out = append(out, *r)
	}
	return out, nil
}

func (f *fakeOpsBookings) FindForAdmin(_ context.Context, id string) (domain.AdminBookingRow, error) {
	r, ok := f.rows[id]
	if !ok {
		return domain.AdminBookingRow{}, repository.ErrBookingNotFound
	}
	return *r, nil
}

func (f *fakeOpsBookings) CancelByOps(_ context.Context, id, reason string, at time.Time) (domain.Booking, error) {
	r, ok := f.rows[id]
	if !ok {
		return domain.Booking{}, repository.ErrBookingNotFound
	}
	b := &r.Booking
	if b.Status == domain.RideStatusCompleted || b.Status == domain.RideStatusCancelled {
		return domain.Booking{}, repository.ErrBookingStateConflict
	}
	b.Status, b.CancelledAt, b.CancelledBy, b.CancelReason = domain.RideStatusCancelled, &at, domain.CancelledByOps, reason
	return *b, nil
}

// fakeOpsPayments settles rows of a fakeOpsBookings.
type fakeOpsPayments struct {
	bookings  *fakeOpsBookings
	attention domain.PaymentAttention
	gotBefore time.Time
}

func (f *fakeOpsPayments) SettleByHand(_ context.Context, id string, mode domain.SettleMode, note string, at time.Time) (domain.Booking, error) {
	r, ok := f.bookings.rows[id]
	if !ok {
		return domain.Booking{}, repository.ErrBookingNotFound
	}
	if r.Booking.Status != domain.RideStatusCompleted || r.Booking.PaidAt != nil {
		return domain.Booking{}, repository.ErrBookingStateConflict
	}
	r.Booking.PaidAt, r.PaidMode, r.PaidNote = &at, string(mode), note
	return r.Booking, nil
}

func (f *fakeOpsPayments) PaymentAttention(_ context.Context, before time.Time, _ int) (domain.PaymentAttention, error) {
	f.gotBefore = before
	return f.attention, nil
}

type fakeAudit struct {
	mu      sync.Mutex
	actions []domain.AdminAction
	err     error
}

func (f *fakeAudit) RecordAction(_ context.Context, a domain.AdminAction) (domain.AdminAction, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return domain.AdminAction{}, f.err
	}
	a.ID = int64(len(f.actions) + 1)
	f.actions = append(f.actions, a)
	return a, nil
}

func (f *fakeAudit) RecentActions(_ context.Context, target string, limit int) ([]domain.AdminAction, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []domain.AdminAction
	for i := len(f.actions) - 1; i >= 0 && len(out) < limit; i-- {
		if target == "" || f.actions[i].Target == target {
			out = append(out, f.actions[i])
		}
	}
	return out, nil
}

type opsAlerts struct {
	assignedCustomer []string // userID
	assignedDriver   []string // driverID
	cancelled        []domain.Booking
}

func (a *opsAlerts) DriverAssigned(_ context.Context, userID string, _ domain.DriverRide, _ string) {
	a.assignedCustomer = append(a.assignedCustomer, userID)
}
func (a *opsAlerts) AssignedByOps(_ context.Context, driverID string, _ domain.DriverRide) {
	a.assignedDriver = append(a.assignedDriver, driverID)
}
func (a *opsAlerts) CancelledByOps(_ context.Context, b domain.Booking, _ tripPlan) {
	a.cancelled = append(a.cancelled, b)
}

// Driver ids the ops tests assign: UUIDs, as the admin page sends.
const (
	opsDriverAuto    = "00000000-0000-4000-8000-00000000a001"
	opsDriverPending = "00000000-0000-4000-8000-00000000a002"
	opsDriverExpired = "00000000-0000-4000-8000-00000000a003"
)

type opsTest struct {
	svc      *OpsService
	bookings *fakeOpsBookings
	payments *fakeOpsPayments
	rides    *fakeRideStore
	audit    *fakeAudit
	alerts   *opsAlerts
}

func newOpsTest(rides ...domain.RideBooking) opsTest {
	bookings := &fakeOpsBookings{rows: map[string]*domain.AdminBookingRow{}}
	for _, rb := range rides {
		bookings.rows[rb.Booking.ID] = &domain.AdminBookingRow{
			Booking: rb.Booking, Customer: domain.AdminParty{ID: "u1", Name: "Asha"},
		}
	}
	lapsed := domain.Date{Time: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)}
	ot := opsTest{
		bookings: bookings,
		payments: &fakeOpsPayments{bookings: bookings},
		rides:    newFakeRideStore(rides...),
		audit:    &fakeAudit{},
		alerts:   &opsAlerts{},
	}
	ot.svc = NewOpsService(OpsDeps{
		Bookings: ot.bookings,
		Rides:    ot.rides,
		Payments: ot.payments,
		Profiles: fakeProfiles{
			opsDriverAuto:    {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionAutomatic, FullName: "Ravi Kumar"},
			opsDriverPending: {KYCStatus: domain.KYCSubmitted, Transmission: domain.DriverTransmissionBoth},
			opsDriverExpired: {KYCStatus: domain.KYCVerified, Transmission: domain.DriverTransmissionBoth, LicenseValidUntil: &lapsed},
		},
		Audit:  ot.audit,
		Alerts: ot.alerts,
	})
	ot.svc.now = func() time.Time { return testNow }
	ot.svc.newCode = func() (string, error) { return "4321", nil }
	return ot
}

var opsMe = Operator{Name: "  Vedanshu  ", IP: "203.0.113.9"}

// Ops can give a ride to a driver after the cutoff that closes it to
// drivers' own taps — that's the point — with the customer and driver told
// and the change audited.
func TestOps_AssignSkipsTheCutoff(t *testing.T) {
	soon := openRide("r1", testNow.Add(20*time.Minute), 2, "automatic") // closed to drivers
	ot := newOpsTest(soon)

	if _, err := ot.svc.Assign(t.Context(), opsMe, "r1", opsDriverAuto); err != nil {
		t.Fatalf("Assign: %v", err)
	}
	rb, _ := ot.rides.FindByID(t.Context(), "r1")
	if rb.Booking.Status != domain.RideStatusAccepted || rb.Booking.DriverID != opsDriverAuto || rb.Booking.StartOTP != "4321" {
		t.Errorf("ride after assign = %+v", rb.Booking)
	}
	if len(ot.alerts.assignedDriver) != 1 || ot.alerts.assignedDriver[0] != opsDriverAuto || len(ot.alerts.assignedCustomer) != 1 {
		t.Errorf("alerts = %+v, want the driver and the customer told", ot.alerts)
	}
	if len(ot.audit.actions) != 1 {
		t.Fatalf("audit = %+v, want one row", ot.audit.actions)
	}
	a := ot.audit.actions[0]
	if a.Actor != "Vedanshu" || a.Action != domain.ActionBookingAssign || a.Target != "r1" ||
		a.Details["driverId"] != opsDriverAuto || a.Details["ip"] != "203.0.113.9" {
		t.Errorf("audit row = %+v", a)
	}
}

func TestOps_AssignRefusals(t *testing.T) {
	start := testNow.Add(3 * time.Hour)
	for _, tc := range []struct {
		name   string
		rides  []domain.RideBooking
		ride   string
		driver string
		want   error
	}{
		{"not cleared", []domain.RideBooking{openRide("r1", start, 2, "manual")}, "r1", opsDriverPending, ErrDriverNotCleared},
		{"licence lapsed", []domain.RideBooking{openRide("r1", start, 2, "manual")}, "r1", opsDriverExpired, ErrDriverNotCleared},
		{"unknown driver", []domain.RideBooking{openRide("r1", start, 2, "manual")}, "r1",
			"00000000-0000-4000-8000-0000000000ff", repository.ErrDriverNotFound},
		{"not a driver id", []domain.RideBooking{openRide("r1", start, 2, "manual")}, "r1", "auto", ErrInvalidOpsRequest},
		{"wrong gearbox", []domain.RideBooking{openRide("r1", start, 2, "manual")}, "r1", opsDriverAuto, ErrTransmissionMismatch},
		{"unknown ride", nil, "nope", opsDriverAuto, repository.ErrRideNotFound},
		{"taken already", []domain.RideBooking{func() domain.RideBooking {
			rb := openRide("r1", start, 2, "automatic")
			rb.Booking.Status, rb.Booking.DriverID = domain.RideStatusAccepted, "someone"
			return rb
		}()}, "r1", opsDriverAuto, repository.ErrRideUnavailable},
		{"clash", []domain.RideBooking{
			openRide("r1", start, 2, "automatic"),
			func() domain.RideBooking {
				rb := openRide("held", start.Add(time.Hour), 2, "automatic")
				rb.Booking.Status, rb.Booking.DriverID = domain.RideStatusAccepted, opsDriverAuto
				return rb
			}(),
		}, "r1", opsDriverAuto, ErrRideClash},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ot := newOpsTest(tc.rides...)
			_, err := ot.svc.Assign(t.Context(), opsMe, tc.ride, tc.driver)
			if !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
			if len(ot.audit.actions) != 0 || len(ot.alerts.assignedDriver) != 0 {
				t.Errorf("a refused assign was audited or announced: %+v %+v", ot.audit.actions, ot.alerts)
			}
		})
	}
}

func TestOps_CancelNeedsAReasonAndTellsBothSides(t *testing.T) {
	rb := openRide("r1", testNow.Add(3*time.Hour), 2, "automatic")
	rb.Booking.Status, rb.Booking.DriverID = domain.RideStatusAccepted, opsDriverAuto
	ot := newOpsTest(rb)

	if _, err := ot.svc.Cancel(t.Context(), opsMe, "r1", "   "); !errors.Is(err, ErrInvalidOpsRequest) {
		t.Fatalf("no reason: err = %v, want ErrInvalidOpsRequest", err)
	}
	got, err := ot.svc.Cancel(t.Context(), opsMe, "r1", "Customer called to cancel")
	if err != nil {
		t.Fatalf("Cancel: %v", err)
	}
	if got.Status != domain.RideStatusCancelled || got.CancelledBy != domain.CancelledByOps {
		t.Errorf("booking = %+v, want cancelled by ops", got)
	}
	if len(ot.alerts.cancelled) != 1 || ot.alerts.cancelled[0].CancelReason != "Customer called to cancel" {
		t.Errorf("cancel alerts = %+v", ot.alerts.cancelled)
	}
	if len(ot.audit.actions) != 1 || ot.audit.actions[0].Action != domain.ActionBookingCancel ||
		ot.audit.actions[0].Details["reason"] != "Customer called to cancel" {
		t.Errorf("audit = %+v", ot.audit.actions)
	}
	if _, err := ot.svc.Cancel(t.Context(), opsMe, "r1", "again"); !errors.Is(err, repository.ErrBookingStateConflict) {
		t.Errorf("second cancel: err = %v, want a state conflict", err)
	}
}

// HUMAN REVIEW REQUIRED: payments. Settling by hand needs a known mode and
// a reason, and is audited with the fare it forgave or the driver took.
func TestOps_SettleByHand(t *testing.T) {
	rb := openRide("r1", testNow.Add(-3*time.Hour), 2, "automatic")
	rb.Booking.Status, rb.Booking.DriverID = domain.RideStatusCompleted, opsDriverAuto
	ot := newOpsTest(rb)

	if _, err := ot.svc.Settle(t.Context(), opsMe, "r1", "card", "paid by card"); !errors.Is(err, ErrInvalidOpsRequest) {
		t.Errorf("unknown mode: err = %v", err)
	}
	if _, err := ot.svc.Settle(t.Context(), opsMe, "r1", domain.SettledCash, ""); !errors.Is(err, ErrInvalidOpsRequest) {
		t.Errorf("no reason: err = %v", err)
	}
	got, err := ot.svc.Settle(t.Context(), opsMe, "r1", domain.SettledCash, "Paid the driver ₹240 cash")
	if err != nil {
		t.Fatalf("Settle: %v", err)
	}
	if got.PaidAt == nil || got.PaidMode != "cash" || got.PaidNote != "Paid the driver ₹240 cash" {
		t.Errorf("booking = %+v, want settled cash", got)
	}
	if len(ot.audit.actions) != 1 {
		t.Fatalf("audit = %+v", ot.audit.actions)
	}
	if a := ot.audit.actions[0]; a.Action != domain.ActionBookingSettle || a.Details["mode"] != "cash" ||
		a.Details["farePaise"] != int64(24000) {
		t.Errorf("audit row = %+v", a)
	}
	if _, err := ot.svc.Settle(t.Context(), opsMe, "r1", domain.SettledWaived, "again"); !errors.Is(err, repository.ErrBookingStateConflict) {
		t.Errorf("second settle: err = %v, want a state conflict", err)
	}
}

// The status filter: "requested" is still open to drivers, "expired" closed
// without a taker, "unpaid" completed and owed.
func TestOps_BookingsFilter(t *testing.T) {
	closes := testNow.Add(acceptCutoff)
	day := func(s string) time.Time {
		d, _ := time.ParseInLocation(time.DateOnly, s, ist)
		return d
	}
	for _, tc := range []struct {
		q          AdminBookingQuery
		wantStatus domain.RideStatus
		wantUnpaid bool
		from, to   time.Time
	}{
		{q: AdminBookingQuery{}},
		{q: AdminBookingQuery{Status: "requested"}, wantStatus: domain.RideStatusRequested, from: closes},
		{q: AdminBookingQuery{Status: "expired"}, wantStatus: domain.RideStatusRequested, to: closes},
		{q: AdminBookingQuery{Status: "unpaid"}, wantUnpaid: true},
		{q: AdminBookingQuery{Status: "completed", From: "2026-10-20", To: "2026-10-21"},
			wantStatus: domain.RideStatusCompleted, from: day("2026-10-20"), to: day("2026-10-22")},
		// An expired list for a past day stays bounded by that day.
		{q: AdminBookingQuery{Status: "expired", From: "2026-10-20", To: "2026-10-20"},
			wantStatus: domain.RideStatusRequested, from: day("2026-10-20"), to: day("2026-10-21")},
	} {
		ot := newOpsTest()
		if _, err := ot.svc.Bookings(t.Context(), tc.q); err != nil {
			t.Fatalf("%+v: %v", tc.q, err)
		}
		f := ot.bookings.gotFilter
		if f.Status != tc.wantStatus || f.Unpaid != tc.wantUnpaid || !f.ScheduledFrom.Equal(tc.from) ||
			!f.ScheduledBefore.Equal(tc.to) || f.Limit != maxAdminBookings {
			t.Errorf("%+v: filter = %+v", tc.q, f)
		}
	}
	for _, bad := range []AdminBookingQuery{{Status: "lost"}, {From: "20/10/2026"}} {
		if _, err := newOpsTest().svc.Bookings(t.Context(), bad); !errors.Is(err, ErrInvalidOpsRequest) {
			t.Errorf("%+v: err = %v, want ErrInvalidOpsRequest", bad, err)
		}
	}
}

func TestOps_BookingsReadsPlacesAndExpiry(t *testing.T) {
	ot := newOpsTest(openRide("closed", testNow.Add(10*time.Minute), 2, "manual"))
	got, err := ot.svc.Bookings(t.Context(), AdminBookingQuery{})
	if err != nil || len(got) != 1 {
		t.Fatalf("Bookings = %+v, %v", got, err)
	}
	if b := got[0]; b.Status != domain.RideStatusExpired || b.Pickup != "India Gate" || b.Car == nil {
		t.Errorf("booking = %+v, want expired, with its pickup and car", b)
	}
}

func TestOps_PaymentAttentionLooksPastTheSweep(t *testing.T) {
	ot := newOpsTest()
	got, err := ot.svc.PaymentAttention(t.Context())
	if err != nil {
		t.Fatalf("PaymentAttention: %v", err)
	}
	if want := testNow.Add(-sweepWindow); !ot.payments.gotBefore.Equal(want) {
		t.Errorf("pending before %v, want %v", ot.payments.gotBefore, want)
	}
	if got.PaidTwice == nil || got.StalePending == nil {
		t.Error("empty lists must be [] in JSON, not null")
	}
}

// The change has happened by the time it's audited: a failed audit write
// is logged, never turned into a failed request.
func TestOps_AuditFailureDoesNotFailTheAction(t *testing.T) {
	rb := openRide("r1", testNow.Add(3*time.Hour), 2, "automatic")
	ot := newOpsTest(rb)
	ot.audit.err = errors.New("db down")
	if _, err := ot.svc.Assign(t.Context(), Operator{}, "r1", opsDriverAuto); err != nil {
		t.Fatalf("Assign: %v", err)
	}
}

func TestOperatorName(t *testing.T) {
	for in, want := range map[string]string{
		"":                  "admin",
		"   ":               "admin",
		"  Asha \n  Singh ": "Asha Singh",
	} {
		if got := OperatorName(in); got != want {
			t.Errorf("OperatorName(%q) = %q, want %q", in, got, want)
		}
	}
	long := ""
	for range 100 {
		long += "é"
	}
	if got := []rune(OperatorName(long)); len(got) != maxOperatorName {
		t.Errorf("long name kept %d characters, want %d", len(got), maxOperatorName)
	}
}
