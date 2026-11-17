package repository

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// rideIn inserts a booking of userID's in status, with driverID ("" none),
// starting at start for fare; it returns the id.
func rideIn(t *testing.T, ctx context.Context, db DB, userID, driverID string, status domain.RideStatus, start time.Time, fare int64) string {
	t.Helper()
	var driver any
	if driverID != "" {
		driver = driverID
	}
	var completed any
	if status == domain.RideStatusCompleted {
		completed = start.Add(2 * time.Hour)
	}
	var id string
	if err := db.QueryRow(ctx, `
		INSERT INTO bookings (user_id, trip_type, details, status, driver_id, scheduled_at, fare_paise, completed_at)
		VALUES ($1, 'roundTrip', '{"hours": 2}', $2, $3, $4, $5, $6)
		RETURNING id`, userID, string(status), driver, start, fare, completed).Scan(&id); err != nil {
		t.Fatalf("inserting ride: %v", err)
	}
	return id
}

func bookingParams(userID string, start time.Time, pickup string) InsertBookingParams {
	return InsertBookingParams{
		UserID:   userID,
		TripType: "roundTrip",
		Details: map[string]any{
			"pickup": map[string]any{"address": pickup, "point": map[string]any{"latitude": 28.6, "longitude": 77.2}},
			"hours":  2.0, "fare": 240.0, "scheduledAt": start.Format("2006-01-02T15:04:05"),
		},
		ScheduledAt: start,
		FarePaise:   24000,
	}
}

// A retried submit finds the first booking: by the app's key, else by being
// the same trip within the window — but never a cancelled one.
func TestBookingRepository_InsertFindsRepeats_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewBookingRepository(tx)
	user := newTestUser(t, ctx, tx)
	start := time.Now().Add(48 * time.Hour).Truncate(time.Second)
	window := time.Now().Add(-10 * time.Minute)

	p := bookingParams(user, start, "India Gate")
	p.IdempotencyKey = "attempt-1"
	first, existing, err := repo.Insert(ctx, p)
	if err != nil || existing {
		t.Fatalf("first insert: existing %v, err %v", existing, err)
	}

	// Same key, even with edited details: the first booking.
	edited := bookingParams(user, start, "Somewhere else")
	edited.IdempotencyKey = "attempt-1"
	if got, existing, err := repo.Insert(ctx, edited); err != nil || !existing || got.ID != first.ID {
		t.Errorf("same key: %s existing %v err %v, want %s", got.ID, existing, err, first.ID)
	}

	// No key, same trip, within the window: the first booking.
	again := bookingParams(user, start, "India Gate")
	again.DuplicateSince = window
	if got, existing, err := repo.Insert(ctx, again); err != nil || !existing || got.ID != first.ID {
		t.Errorf("same trip: %s existing %v err %v, want %s", got.ID, existing, err, first.ID)
	}

	// A different trip, or no window, is a new booking.
	other := bookingParams(user, start, "Connaught Place")
	other.DuplicateSince = window
	if got, existing, err := repo.Insert(ctx, other); err != nil || existing || got.ID == first.ID {
		t.Errorf("other trip: %s existing %v err %v, want a new booking", got.ID, existing, err)
	}
	if got, existing, err := repo.Insert(ctx, bookingParams(user, start, "India Gate")); err != nil || existing || got.ID == first.ID {
		t.Errorf("no window: %s existing %v err %v, want a new booking", got.ID, existing, err)
	}

	// Once the customer cancels, booking the same trip again is a new one.
	if _, err := tx.Exec(ctx, `UPDATE bookings SET status = 'cancelled' WHERE user_id = $1`, user); err != nil {
		t.Fatal(err)
	}
	if got, existing, err := repo.Insert(ctx, again); err != nil || existing {
		t.Errorf("after cancel: %s existing %v err %v, want a new booking", got.ID, existing, err)
	}
}

// HUMAN REVIEW REQUIRED: payments. An unpaid ride blocks the customer until
// it's paid or settled by hand. A ride settled in cash is never owed to its
// driver; a waived one is owed their usual share (MOJUD pays it). The
// receipt says how.
func TestPaymentRepository_SettleByHand_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	bookings, payments := NewBookingRepository(tx), NewPaymentRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	yesterday := time.Now().Add(-24 * time.Hour)

	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != "" {
		t.Fatalf("no rides: unpaid %q, %v", id, err)
	}
	rideIn(t, ctx, tx, user, driver, domain.RideStatusCompleted, yesterday, 50) // below the gateway minimum
	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != "" {
		t.Fatalf("an unpayable fare blocked the customer: %q, %v", id, err)
	}
	ride := rideIn(t, ctx, tx, user, driver, domain.RideStatusCompleted, yesterday, 24000)
	open := rideIn(t, ctx, tx, user, "", domain.RideStatusRequested, time.Now().Add(48*time.Hour), 24000)
	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != ride {
		t.Fatalf("unpaid = %q, %v; want %s", id, err, ride)
	}

	b, err := payments.SettleByHand(ctx, ride, domain.SettledCash, "Paid the driver in cash", 1300, time.Now())
	if err != nil {
		t.Fatalf("SettleByHand: %v", err)
	}
	if b.PaidAt == nil || b.PaidPaise != 0 || b.CommissionPaise != 0 {
		t.Errorf("settled booking = %+v, want paid with nothing received", b)
	}
	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != "" {
		t.Errorf("after settling: unpaid %q, %v", id, err)
	}

	for _, tc := range []struct {
		id   string
		want error
	}{
		{ride, ErrBookingStateConflict}, // already paid
		{open, ErrBookingStateConflict}, // not completed
		{"00000000-0000-4000-8000-000000000000", ErrBookingNotFound},
		{"not-a-uuid", ErrBookingNotFound},
	} {
		// In a savepoint: a malformed id aborts the statement's transaction.
		err := inSavepoint(t, ctx, tx, func(db DB) error {
			_, err := NewPaymentRepository(db).SettleByHand(ctx, tc.id, domain.SettledWaived, "x", 1300, time.Now())
			return err
		})
		if !errors.Is(err, tc.want) {
			t.Errorf("settle %s: err = %v, want %v", tc.id, err, tc.want)
		}
	}

	ub, err := bookings.FindForUser(ctx, ride, user)
	if err != nil {
		t.Fatalf("FindForUser: %v", err)
	}
	if ub.Payment == nil || ub.Payment.Mode != "CASH" || ub.Payment.MerchantOrderID != "" || ub.Payment.PaidAt.IsZero() {
		t.Errorf("receipt = %+v, want CASH with no order", ub.Payment)
	}

	// A ride with a UPI checkout pending or paid is not settled by hand; a
	// failed one doesn't block.
	other := rideIn(t, ctx, tx, user, driver, domain.RideStatusCompleted, yesterday, 18000)
	if err := payments.InsertOrder(ctx, domain.PaymentOrder{
		MerchantOrderID: "MOJUD_settle_guard", BookingID: other, UserID: user, AmountPaise: 18000,
		ProviderOrderID: "OMO-settle", ExpiresAt: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatalf("InsertOrder: %v", err)
	}
	for _, state := range []string{"pending", "completed"} {
		if _, err := tx.Exec(ctx, `UPDATE payment_orders SET state = $2 WHERE merchant_order_id = $1`,
			"MOJUD_settle_guard", state); err != nil {
			t.Fatal(err)
		}
		if _, err := payments.SettleByHand(ctx, other, domain.SettledWaived, "x", 1300, time.Now()); !errors.Is(err, ErrGatewayOrderOpen) ||
			!errors.Is(err, ErrBookingStateConflict) {
			t.Errorf("%s order: err = %v, want ErrGatewayOrderOpen", state, err)
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE payment_orders SET state = 'failed' WHERE merchant_order_id = 'MOJUD_settle_guard'`); err != nil {
		t.Fatal(err)
	}
	waived, err := payments.SettleByHand(ctx, other, domain.SettledWaived, "x", 1300, time.Now())
	if err != nil {
		t.Fatalf("failed order: err = %v, want settled", err)
	}
	// ₹180 waived: MOJUD covers it, keeps its 13% (₹23.40), owes the driver ₹156.60.
	if waived.PaidPaise != 18000 || waived.CommissionPaise != 2340 {
		t.Errorf("waived booking paid %d commission %d, want 18000 / 2340", waived.PaidPaise, waived.CommissionPaise)
	}

	// Only the waived ride is owed — the cash one never is.
	due, err := payments.DuePayouts(ctx, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	var owed []domain.PayoutDue
	for _, d := range due {
		if d.DriverID == driver {
			owed = append(owed, d)
		}
	}
	if len(owed) != 1 || owed[0].Rides != 1 || owed[0].AmountPaise != 15660 {
		t.Errorf("owed to the driver = %+v, want the waived ride's 15660", owed)
	}
	p, err := payments.RecordPayout(ctx, driver, "UTR", time.Now(), time.Now(), ExpectedPayout{})
	if err != nil || p.Rides != 1 || p.AmountPaise != 15660 {
		t.Errorf("payout = %+v, %v; want the waived ride only", p, err)
	}
}

// HUMAN REVIEW REQUIRED: payments. A cancellation at the pickup charges the
// fee only when allowed; the fee blocks the next booking until it's paid
// or settled, and a waived fee is owed to the driver like a ride. A trip
// ended early keeps its booked fare.
func TestBookingRepository_CancellationCharges_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	bookings, payments := NewBookingRepository(tx), NewPaymentRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	soon := time.Now().Add(time.Hour)
	fee := PickupCancel{Allowed: true, FeePaise: domain.CancellationFeePaise}

	// On the way: free, even with a fee on offer.
	coming := rideIn(t, ctx, tx, user, driver, domain.RideStatusAccepted, soon, 44000)
	b, err := bookings.Cancel(ctx, coming, user, "", time.Now(), fee)
	if err != nil || b.CancellationFeePaise != 0 {
		t.Fatalf("Cancel(accepted) = fee %d, %v; want free", b.CancellationFeePaise, err)
	}

	// At the pickup, not allowed: refused, unchanged.
	waiting := rideIn(t, ctx, tx, user, driver, domain.RideStatusArrived, soon, 44000)
	if _, err := bookings.Cancel(ctx, waiting, user, "", time.Now(), PickupCancel{FeePaise: fee.FeePaise}); !errors.Is(err, ErrBookingStateConflict) {
		t.Fatalf("Cancel(arrived, not allowed) err = %v, want ErrBookingStateConflict", err)
	}
	// Allowed: cancelled with the fee, which now blocks the next booking.
	b, err = bookings.Cancel(ctx, waiting, user, "Changed plans", time.Now(), fee)
	if err != nil || b.Status != domain.RideStatusCancelled || b.CancellationFeePaise != fee.FeePaise ||
		b.PaymentStatus() != domain.RidePaymentDue {
		t.Fatalf("Cancel(arrived) = %+v, %v; want cancelled with the fee due", b, err)
	}
	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != waiting {
		t.Errorf("unpaid = %q, %v; want the fee %s", id, err, waiting)
	}

	// Waived: the customer may book again, and MOJUD owes the driver ₹43.50.
	if _, err := payments.SettleByHand(ctx, waiting, domain.SettledWaived, "goodwill", 1300, time.Now()); err != nil {
		t.Fatalf("SettleByHand(fee): %v", err)
	}
	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != "" {
		t.Errorf("after waiving: unpaid %q, %v", id, err)
	}
	due, err := payments.DuePayouts(ctx, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, d := range due {
		if d.DriverID == driver {
			found = d.AmountPaise == 4350 && d.Rides == 1
		}
	}
	if !found {
		t.Errorf("waived fee not owed to the driver as 4350: %+v", due)
	}
	// A free cancellation has nothing to settle.
	if _, err := payments.SettleByHand(ctx, coming, domain.SettledCash, "x", 1300, time.Now()); !errors.Is(err, ErrBookingStateConflict) {
		t.Errorf("settle a free cancellation: err = %v, want ErrBookingStateConflict", err)
	}

	// Ended early: completed at the charge, the booked fare kept; only in progress.
	driving := rideIn(t, ctx, tx, user, driver, domain.RideStatusInProgress, time.Now().Add(-time.Hour), 44000)
	b, err = bookings.EndEarly(ctx, driving, user, 24000, time.Now())
	if err != nil || b.Status != domain.RideStatusCompleted || b.FarePaise != 24000 || b.BookedFarePaise != 44000 ||
		b.CompletedAt == nil {
		t.Fatalf("EndEarly = %+v, %v; want completed at 24000, booked 44000", b, err)
	}
	if _, err := bookings.EndEarly(ctx, driving, user, 13900, time.Now()); !errors.Is(err, ErrBookingStateConflict) {
		t.Errorf("EndEarly twice: err = %v, want ErrBookingStateConflict", err)
	}
	if id, err := bookings.UnpaidRide(ctx, user, 100); err != nil || id != driving {
		t.Errorf("unpaid = %q, %v; want the ended trip %s", id, err, driving)
	}
}

// A ride paid twice is a refund to make; an order pending past the sweep is
// one nobody is checking. Both are listed; a normal payment isn't. The
// customer's receipt carries the order that paid.
func TestPaymentRepository_AttentionAndReceipt_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	bookings, payments := NewBookingRepository(tx), NewPaymentRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	ride := rideIn(t, ctx, tx, user, driver, domain.RideStatusCompleted, time.Now().Add(-3*time.Hour), 24000)
	suffix := ride[:8]
	order := func(id string) domain.PaymentOrder {
		o := domain.PaymentOrder{MerchantOrderID: id + suffix, BookingID: ride, UserID: user, AmountPaise: 24000,
			ProviderOrderID: "OMO" + id, ExpiresAt: time.Now().Add(15 * time.Minute)}
		if err := payments.InsertOrder(ctx, o); err != nil {
			t.Fatalf("InsertOrder %s: %v", id, err)
		}
		return o
	}
	first, second, stale := order("A"), order("B"), order("C")
	paid := domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 24000,
		TransactionID: "T1", PaymentMode: "UPI_INTENT", UTR: "412345678901"}
	if out, _, err := payments.CompleteOrder(ctx, first, paid, 3120, time.Now()); err != nil || out != domain.SettledNow {
		t.Fatalf("first CompleteOrder: %v, %v", out, err)
	}
	if out, _, err := payments.CompleteOrder(ctx, second, paid, 3120, time.Now()); err != nil || out != domain.SettledPaidTwice {
		t.Fatalf("second CompleteOrder: %v, %v", out, err)
	}
	if _, err := tx.Exec(ctx, `UPDATE payment_orders SET created_at = now() - interval '2 days' WHERE merchant_order_id = $1`,
		stale.MerchantOrderID); err != nil {
		t.Fatal(err)
	}

	att, err := payments.PaymentAttention(ctx, time.Now().Add(-24*time.Hour), 1000)
	if err != nil {
		t.Fatalf("PaymentAttention: %v", err)
	}
	byOrder := func(list []domain.AttentionOrder) map[string]domain.AttentionOrder {
		m := map[string]domain.AttentionOrder{}
		for _, o := range list {
			if o.BookingID == ride {
				m[o.MerchantOrderID] = o
			}
		}
		return m
	}
	twice, pending := byOrder(att.PaidTwice), byOrder(att.StalePending)
	if len(twice) != 1 || twice[second.MerchantOrderID].PaidBy != first.MerchantOrderID ||
		twice[second.MerchantOrderID].UTR != "412345678901" {
		t.Errorf("paid twice = %+v, want only %s, paid by %s", twice, second.MerchantOrderID, first.MerchantOrderID)
	}
	if len(pending) != 1 || pending[stale.MerchantOrderID].State != domain.PaymentPending {
		t.Errorf("stale pending = %+v, want only %s", pending, stale.MerchantOrderID)
	}

	ub, err := bookings.FindForUser(ctx, ride, user)
	if err != nil {
		t.Fatalf("FindForUser: %v", err)
	}
	if p := ub.Payment; p == nil || p.Mode != "UPI_INTENT" || p.UTR != "412345678901" || p.TransactionID != "T1" ||
		p.MerchantOrderID != first.MerchantOrderID {
		t.Errorf("receipt = %+v", p)
	}
}

func TestBookingRepository_AdminListAndCancel_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewBookingRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	// A day nobody else's test rides fall on.
	day := time.Date(2031, 3, 14, 10, 0, 0, 0, time.UTC)
	open := rideIn(t, ctx, tx, user, "", domain.RideStatusRequested, day, 24000)
	unpaid := rideIn(t, ctx, tx, user, driver, domain.RideStatusCompleted, day.Add(time.Hour), 24000)
	driving := rideIn(t, ctx, tx, user, driver, domain.RideStatusInProgress, day.Add(2*time.Hour), 24000)
	window := AdminBookingFilter{ScheduledFrom: day.Add(-time.Hour), ScheduledBefore: day.Add(24 * time.Hour), Limit: 50}

	ids := func(f AdminBookingFilter) map[string]domain.AdminBookingRow {
		rows, err := repo.ListForAdmin(ctx, f)
		if err != nil {
			t.Fatalf("ListForAdmin(%+v): %v", f, err)
		}
		m := map[string]domain.AdminBookingRow{}
		for _, r := range rows {
			m[r.Booking.ID] = r
		}
		return m
	}
	all := ids(window)
	if len(all) != 3 {
		t.Fatalf("window lists %d bookings, want 3", len(all))
	}
	if r := all[unpaid]; r.Customer.Name != "Test Customer" || r.Driver == nil || r.Driver.ID != driver || r.Driver.Name != "Test Driver" {
		t.Errorf("row = %+v", r)
	}
	if r := all[open]; r.Driver != nil {
		t.Errorf("an open ride has a driver: %+v", r.Driver)
	}
	f := window
	f.Unpaid = true
	if got := ids(f); len(got) != 1 || got[unpaid].Booking.ID == "" {
		t.Errorf("unpaid filter = %v", got)
	}
	f = window
	f.Status = domain.RideStatusRequested
	if got := ids(f); len(got) != 1 || got[open].Booking.ID == "" {
		t.Errorf("status filter = %v", got)
	}

	// Ops can cancel up to and including a trip underway, never a finished one.
	for _, id := range []string{open, driving} {
		b, err := repo.CancelByOps(ctx, id, "ops test", day)
		if err != nil || b.Status != domain.RideStatusCancelled || b.CancelledBy != domain.CancelledByOps || b.CancelReason != "ops test" {
			t.Errorf("CancelByOps(%s) = %+v, %v", id, b, err)
		}
	}
	if _, err := repo.CancelByOps(ctx, unpaid, "x", day); !errors.Is(err, ErrBookingStateConflict) {
		t.Errorf("cancelling a completed ride: err = %v", err)
	}
	if _, err := repo.CancelByOps(ctx, "00000000-0000-4000-8000-000000000000", "x", day); !errors.Is(err, ErrBookingNotFound) {
		t.Errorf("unknown booking: err = %v", err)
	}
	if r, err := repo.FindForAdmin(ctx, open); err != nil || r.Booking.Status != domain.RideStatusCancelled {
		t.Errorf("FindForAdmin = %+v, %v", r.Booking, err)
	}
}

func TestAdminActionRepository_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewAdminActionRepository(tx)
	target := "booking-" + time.Now().Format("150405.000000")

	first, err := repo.RecordAction(ctx, domain.AdminAction{Actor: "Asha", Action: domain.ActionBookingCancel, Target: target,
		Details: map[string]any{"reason": "customer asked", "ip": "203.0.113.9"}, At: time.Now().Add(-time.Minute)})
	if err != nil || first.ID == 0 {
		t.Fatalf("RecordAction: %+v, %v", first, err)
	}
	if _, err := repo.RecordAction(ctx, domain.AdminAction{Actor: "admin", Action: domain.ActionPayoutRecord, Target: "elsewhere"}); err != nil {
		t.Fatalf("RecordAction without details or time: %v", err)
	}
	second, err := repo.RecordAction(ctx, domain.AdminAction{Actor: "Ravi", Action: domain.ActionBookingSettle, Target: target})
	if err != nil {
		t.Fatal(err)
	}

	got, err := repo.RecentActions(ctx, target, 10)
	if err != nil {
		t.Fatalf("RecentActions: %v", err)
	}
	if len(got) != 2 || got[0].ID != second.ID || got[1].ID != first.ID {
		t.Fatalf("actions = %+v, want the two on %s, newest first", got, target)
	}
	if got[1].Details["reason"] != "customer asked" || got[1].Actor != "Asha" {
		t.Errorf("details didn't round-trip: %+v", got[1])
	}
}

func TestPaymentRepository_PayoutsForDriver_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewPaymentRepository(tx)
	driver, other := newTestDriver(t, ctx, tx), newTestDriver(t, ctx, tx)
	at := time.Date(2026, 11, 1, 12, 0, 0, 0, time.UTC)
	for i, p := range []struct {
		driver string
		ref    string
		at     time.Time
	}{{driver, "UTR-old", at}, {driver, "UTR-new", at.Add(48 * time.Hour)}, {other, "UTR-theirs", at}} {
		if _, err := tx.Exec(ctx, `INSERT INTO driver_payouts (driver_id, amount_paise, rides, reference, created_at)
			VALUES ($1, $2, 1, $3, $4)`, p.driver, 1000*(i+1), p.ref, p.at); err != nil {
			t.Fatal(err)
		}
	}
	got, err := repo.PayoutsForDriver(ctx, driver, 50)
	if err != nil {
		t.Fatalf("PayoutsForDriver: %v", err)
	}
	if len(got) != 2 || got[0].Reference != "UTR-new" || got[1].Reference != "UTR-old" || got[0].DriverID != driver {
		t.Errorf("payouts = %+v, want the driver's two, newest first", got)
	}
}

// Two copies of one submit racing in — a double tap, a retry crossing the
// first response — make one booking: the per-customer lock serialises the
// look-up and the insert. Needs a pool (real concurrency), so it commits
// and cleans up.
func TestBookingRepository_ConcurrentRepeatsMakeOneBooking_Integration(t *testing.T) {
	pool := testDB(t)
	ctx := context.Background()
	user := newTestUser(t, ctx, pool)
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bookings WHERE user_id = $1`, user)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, user)
	})
	repo := NewBookingRepository(pool)
	start := time.Now().Add(48 * time.Hour).Truncate(time.Second)

	for _, keyed := range []bool{true, false} {
		p := bookingParams(user, start, "Race unkeyed")
		p.DuplicateSince = time.Now().Add(-10 * time.Minute)
		if keyed {
			p = bookingParams(user, start, "Race keyed")
			p.IdempotencyKey = "race-key"
		}
		const n = 8
		type result struct {
			id       string
			existing bool
			err      error
		}
		results := make(chan result, n)
		for range n {
			go func() {
				b, existing, err := repo.Insert(ctx, p)
				results <- result{b.ID, existing, err}
			}()
		}
		ids, created := map[string]bool{}, 0
		for range n {
			r := <-results
			if r.err != nil {
				t.Fatalf("keyed=%v: Insert: %v", keyed, r.err)
			}
			ids[r.id] = true
			if !r.existing {
				created++
			}
		}
		if len(ids) != 1 || created != 1 {
			t.Errorf("keyed=%v: %d ids, %d created; want one booking made once", keyed, len(ids), created)
		}
	}
}

// The driver's net share: what was paid less commission, unpaid fares less
// commission at the configured rate, the whole fare of a cash ride, and the
// usual share of a waived one (MOJUD pays it). Earnings needs a pool, so
// this commits and cleans up.
func TestDriverRideRepository_EarningsNet_Integration(t *testing.T) {
	pool := testDB(t)
	ctx := context.Background()
	user, driver := newTestUser(t, ctx, pool), newTestDriver(t, ctx, pool)
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bookings WHERE driver_id = $1`, driver)
		_, _ = pool.Exec(ctx, `DELETE FROM drivers WHERE id = $1`, driver)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, user)
	})
	when := time.Now().Add(-3 * time.Hour)
	paidRide(t, ctx, pool, user, driver, when, 30000, 3900)                     // net 26100
	rideIn(t, ctx, pool, user, driver, domain.RideStatusCompleted, when, 24000) // unpaid: 24000 - 3120
	payments := NewPaymentRepository(pool)
	for _, s := range []struct {
		fare int64
		mode domain.SettleMode
	}{{20000, domain.SettledCash}, {10000, domain.SettledWaived}} {
		id := rideIn(t, ctx, pool, user, driver, domain.RideStatusCompleted, when, s.fare)
		if _, err := payments.SettleByHand(ctx, id, s.mode, "test", 1300, time.Now()); err != nil {
			t.Fatal(err)
		}
	}

	repo := NewDriverRideRepository(pool)
	repo.SetCommissionBasisPoints(1300)
	far := time.Now().Add(-365 * 24 * time.Hour)
	e, err := repo.Earnings(ctx, driver, far, far, far)
	if err != nil {
		t.Fatalf("Earnings: %v", err)
	}
	const wantNet = 26100 + 20880 + 20000 + 8700
	if e.Total.FarePaise != 84000 || e.Total.NetPaise != wantNet || e.Today.NetPaise != wantNet {
		t.Errorf("total = %+v, today = %+v; want fares 84000, net %d", e.Total, e.Today, wantNet)
	}
	// The gateway payment and the waived ride are owed to the driver; the
	// cash one isn't.
	if e.Payments.DuePaise != 26100+8700 || e.Payments.DueRides != 2 ||
		e.Payments.AwaitingCustomerPaise != 24000 || e.Payments.AwaitingCustomerRides != 1 {
		t.Errorf("payments = %+v", e.Payments)
	}
}
