package repository

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// testDB opens the database named by SARTHI_TEST_DATABASE_URL, or skips.
// Only a database on this machine is accepted — these tests write rows (and
// roll them back), so they must never be pointed at production.
//
//	SARTHI_TEST_DATABASE_URL='postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable' \
//	  go test ./internal/repository/ -run Integration -count=1 -v
func testDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("SARTHI_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("SARTHI_TEST_DATABASE_URL not set; start the local DB with ./scripts/run-backend.sh")
	}
	u, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("SARTHI_TEST_DATABASE_URL: %v", err)
	}
	if h := u.Hostname(); h != "localhost" && h != "127.0.0.1" && h != "::1" {
		t.Fatalf("SARTHI_TEST_DATABASE_URL must point at localhost, not %q", h)
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connecting: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestStatsRepository_Integration(t *testing.T) {
	ctx := context.Background()
	tx, err := testDB(t).Begin(ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	ist := time.FixedZone("IST", 5*60*60+30*60)
	now := time.Date(2026, 11, 1, 12, 0, 0, 0, ist)
	today := time.Date(2026, 11, 1, 0, 0, 0, 0, ist)
	q := StatsQuery{
		Now:          now,
		ClosesBefore: now.Add(30 * time.Minute),
		Today:        today,
		Last7Days:    today.AddDate(0, 0, -6),
		Last30Days:   today.AddDate(0, 0, -29),
	}
	repo := NewStatsRepository(tx)

	before, err := repo.Stats(ctx, q)
	if err != nil {
		t.Fatalf("Stats (baseline): %v", err)
	}

	// --- fixtures, all rolled back ------------------------------------------
	tag := time.Now().UnixNano() % 1_000_000_000
	insert := func(sql string, args ...any) string {
		t.Helper()
		var id string
		if err := tx.QueryRow(ctx, sql+" RETURNING id", args...).Scan(&id); err != nil {
			t.Fatalf("fixture %q: %v", sql, err)
		}
		return id
	}
	customer := func(i int) string {
		return insert(`INSERT INTO users (phone_e164, name, email, date_of_birth)
			VALUES ($1, 'Stats Test', 'stats@example.test', '1990-01-01')`,
			fmt.Sprintf("+0stats%09d%d", tag, i))
	}
	driver := func(i int, kyc string) string {
		return insert(`INSERT INTO drivers (phone_e164, name, kyc_status) VALUES ($1, 'Stats Driver', $2)`,
			fmt.Sprintf("+0statsd%09d%d", tag, i), kyc)
	}
	u1 := customer(1)
	customer(2)
	d1 := driver(1, "verified")
	d2 := driver(2, "submitted")
	driver(3, "rejected")
	driver(4, "incomplete")

	type ride struct {
		status      string
		driver      string
		scheduledAt time.Time
		fare        int64
		completedAt *time.Time
		paidAt      *time.Time
		paid, cut   int64
	}
	at := func(t time.Time) *time.Time { return &t }
	book := func(r ride) string {
		var driverID any
		if r.driver != "" {
			driverID = r.driver
		}
		var paid, cut any
		if r.paidAt != nil {
			paid, cut = r.paid, r.cut
		}
		return insert(`INSERT INTO bookings
			(user_id, trip_type, details, status, driver_id, scheduled_at, fare_paise,
			 completed_at, paid_at, paid_paise, commission_paise)
			VALUES ($1, 'roundTrip', '{}', $2, $3, $4, $5, $6, $7, $8, $9)`,
			u1, r.status, driverID, r.scheduledAt, r.fare, r.completedAt, r.paidAt, paid, cut)
	}
	later := now.Add(2 * time.Hour)
	book(ride{status: "requested", scheduledAt: later})                       // open
	book(ride{status: "requested", scheduledAt: q.ClosesBefore})              // open: exactly at the cutoff
	book(ride{status: "requested", scheduledAt: now.Add(10 * time.Minute)})   // expired
	book(ride{status: "accepted", driver: d1, scheduledAt: later})            // accepted
	book(ride{status: "arrived", driver: d1, scheduledAt: now})               // accepted
	book(ride{status: "in_progress", driver: d1, scheduledAt: now})           // in progress
	book(ride{status: "cancelled", driver: d1, scheduledAt: later})           // cancelled
	book(ride{status: "completed", driver: d1, scheduledAt: now, fare: 10000, // today, paid, owed 8700
		completedAt: at(now.Add(-time.Hour)), paidAt: at(now.Add(-50 * time.Minute)), paid: 10000, cut: 1300})
	book(ride{status: "completed", driver: d1, scheduledAt: today, fare: 1000, // today: exactly midnight
		completedAt: at(today)})
	book(ride{status: "completed", driver: d1, scheduledAt: today, fare: 20000, // yesterday 23:59:59
		completedAt: at(today.Add(-time.Second))})
	book(ride{status: "completed", driver: d2, scheduledAt: today, fare: 5000, // 2 days ago, paid, owed 4350
		completedAt: at(now.AddDate(0, 0, -2)), paidAt: at(now.AddDate(0, 0, -2)), paid: 5000, cut: 650})
	paidOut := book(ride{status: "completed", driver: d1, scheduledAt: today, fare: 30000, // last 30 only, paid out
		completedAt: at(q.Last7Days.Add(-time.Second)), paidAt: at(q.Last7Days), paid: 30000, cut: 3900})
	book(ride{status: "completed", driver: d1, scheduledAt: today, fare: 40000, // older than 30 days
		completedAt: at(q.Last30Days.Add(-time.Second))})

	payout := insert(`INSERT INTO driver_payouts (driver_id, amount_paise, rides, reference)
		VALUES ($1, 26100, 1, 'UTR-STATS-TEST')`, d1)
	if _, err := tx.Exec(ctx, `UPDATE bookings SET payout_id = $1 WHERE id = $2`, payout, paidOut); err != nil {
		t.Fatalf("marking paid out: %v", err)
	}

	after, err := repo.Stats(ctx, q)
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}

	deltas := []struct {
		name        string
		before, now int64
		want        int64
	}{
		{"users.customers", int64(before.Users.Customers), int64(after.Users.Customers), 2},
		{"users.drivers", int64(before.Users.Drivers), int64(after.Users.Drivers), 4},
		{"kyc.incomplete", int64(before.DriversByKYC.Incomplete), int64(after.DriversByKYC.Incomplete), 1},
		{"kyc.submitted", int64(before.DriversByKYC.Submitted), int64(after.DriversByKYC.Submitted), 1},
		{"kyc.verified", int64(before.DriversByKYC.Verified), int64(after.DriversByKYC.Verified), 1},
		{"kyc.rejected", int64(before.DriversByKYC.Rejected), int64(after.DriversByKYC.Rejected), 1},
		{"bookings.open", int64(before.BookingsByStatus.Open), int64(after.BookingsByStatus.Open), 2},
		{"bookings.expired", int64(before.BookingsByStatus.Expired), int64(after.BookingsByStatus.Expired), 1},
		{"bookings.accepted", int64(before.BookingsByStatus.Accepted), int64(after.BookingsByStatus.Accepted), 2},
		{"bookings.inProgress", int64(before.BookingsByStatus.InProgress), int64(after.BookingsByStatus.InProgress), 1},
		{"bookings.completed", int64(before.BookingsByStatus.Completed), int64(after.BookingsByStatus.Completed), 6},
		{"bookings.cancelled", int64(before.BookingsByStatus.Cancelled), int64(after.BookingsByStatus.Cancelled), 1},
		{"bookings.total", int64(before.BookingsByStatus.Total), int64(after.BookingsByStatus.Total), 13},
		{"today.rides", int64(before.CompletedRides.Today.Rides), int64(after.CompletedRides.Today.Rides), 2},
		{"today.gross", before.CompletedRides.Today.GrossFarePaise, after.CompletedRides.Today.GrossFarePaise, 11000},
		{"last7.rides", int64(before.CompletedRides.Last7Days.Rides), int64(after.CompletedRides.Last7Days.Rides), 4},
		{"last7.gross", before.CompletedRides.Last7Days.GrossFarePaise, after.CompletedRides.Last7Days.GrossFarePaise, 36000},
		{"last30.rides", int64(before.CompletedRides.Last30Days.Rides), int64(after.CompletedRides.Last30Days.Rides), 5},
		{"last30.gross", before.CompletedRides.Last30Days.GrossFarePaise, after.CompletedRides.Last30Days.GrossFarePaise, 66000},
		{"payoutsDue.drivers", int64(before.PayoutsDue.Drivers), int64(after.PayoutsDue.Drivers), 2},
		{"payoutsDue.rides", int64(before.PayoutsDue.Rides), int64(after.PayoutsDue.Rides), 2},
		{"payoutsDue.amount", before.PayoutsDue.AmountPaise, after.PayoutsDue.AmountPaise, 13050},
	}
	for _, d := range deltas {
		if got := d.now - d.before; got != d.want {
			t.Errorf("%s: +%d, want +%d (before %d, after %d)", d.name, got, d.want, d.before, d.now)
		}
	}

	// The total owed must agree with the payouts list it summarises.
	due, err := duePayoutsTotal(ctx, tx, now)
	if err != nil {
		t.Fatalf("summing due payouts: %v", err)
	}
	if after.PayoutsDue != due {
		t.Errorf("payoutsDue = %+v, but GET /admin/payouts/due sums to %+v", after.PayoutsDue, due)
	}
}

// duePayoutsTotal sums PaymentRepository.DuePayouts' query at asOf, so the
// test pins the stats figure to the list the back office pays from.
func duePayoutsTotal(ctx context.Context, tx pgx.Tx, asOf time.Time) (domain.StatsPayoutsDue, error) {
	rows, err := tx.Query(ctx, `
		SELECT count(*), sum(b.paid_paise - coalesce(b.commission_paise, 0))
		FROM bookings b
		JOIN drivers d ON d.id = b.driver_id
		WHERE b.paid_at IS NOT NULL AND b.payout_id IS NULL AND b.paid_at <= $1
		GROUP BY d.id`, asOf)
	if err != nil {
		return domain.StatsPayoutsDue{}, err
	}
	defer rows.Close()
	var out domain.StatsPayoutsDue
	for rows.Next() {
		var (
			rides  int
			amount int64
		)
		if err := rows.Scan(&rides, &amount); err != nil {
			return domain.StatsPayoutsDue{}, err
		}
		out.Drivers++
		out.Rides += rides
		out.AmountPaise += amount
	}
	return out, rows.Err()
}
