package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// RowQuerier runs a single-row query: a *pgxpool.Pool, or a pgx.Tx in tests.
type RowQuerier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// StatsRepository reads the ops dashboard's counts. Read-only.
type StatsRepository struct {
	db RowQuerier
}

// NewStatsRepository wires the repository to a pool (or a transaction).
func NewStatsRepository(db RowQuerier) *StatsRepository {
	return &StatsRepository{db: db}
}

// StatsQuery is the moment the numbers are read at, with the boundaries the
// service worked out from it.
type StatsQuery struct {
	// Now bounds the payouts due: rides paid by now.
	Now time.Time
	// ClosesBefore splits requested rides: one starting before it is closed
	// to drivers (expired), the rest are open.
	ClosesBefore time.Time
	// Today, Last7Days and Last30Days start the completed-ride windows.
	Today, Last7Days, Last30Days time.Time
}

// statsSQL reads every count in one statement. Bookings are scanned once;
// a completed ride counts in a window by when it was completed.
const statsSQL = `
	WITH d AS (
	    SELECT count(*) AS total,
	           count(*) FILTER (WHERE kyc_status = 'incomplete') AS incomplete,
	           count(*) FILTER (WHERE kyc_status = 'submitted')  AS submitted,
	           count(*) FILTER (WHERE kyc_status = 'verified')   AS verified,
	           count(*) FILTER (WHERE kyc_status = 'rejected')   AS rejected
	    FROM drivers
	), b AS (
	    SELECT count(*) AS total,
	           count(*) FILTER (WHERE status = 'requested'
	                              AND (scheduled_at IS NULL OR scheduled_at >= $1)) AS open,
	           count(*) FILTER (WHERE status = 'requested' AND scheduled_at < $1)   AS expired,
	           count(*) FILTER (WHERE status IN ('accepted', 'arrived'))            AS accepted,
	           count(*) FILTER (WHERE status = 'in_progress')                       AS in_progress,
	           count(*) FILTER (WHERE status = 'completed')                         AS completed,
	           count(*) FILTER (WHERE status = 'cancelled')                         AS cancelled,
	           count(*) FILTER (WHERE status = 'completed' AND completed_at >= $2)  AS today_rides,
	           coalesce(sum(fare_paise) FILTER (WHERE status = 'completed' AND completed_at >= $2), 0)::bigint AS today_fare,
	           count(*) FILTER (WHERE status = 'completed' AND completed_at >= $3)  AS week_rides,
	           coalesce(sum(fare_paise) FILTER (WHERE status = 'completed' AND completed_at >= $3), 0)::bigint AS week_fare,
	           count(*) FILTER (WHERE status = 'completed' AND completed_at >= $4)  AS month_rides,
	           coalesce(sum(fare_paise) FILTER (WHERE status = 'completed' AND completed_at >= $4), 0)::bigint AS month_fare
	    FROM bookings
	), p AS (
	    -- The same rides PaymentRepository.DuePayouts lists.
	    SELECT count(DISTINCT driver_id) AS drivers,
	           count(*) AS rides,
	           coalesce(sum(paid_paise - coalesce(commission_paise, 0)), 0)::bigint AS amount
	    FROM bookings
	    WHERE paid_at IS NOT NULL AND payout_id IS NULL AND paid_at <= $5
	      AND driver_id IS NOT NULL
	)
	SELECT (SELECT count(*) FROM users),
	       d.total, d.incomplete, d.submitted, d.verified, d.rejected,
	       b.open, b.accepted, b.in_progress, b.completed, b.cancelled, b.expired, b.total,
	       b.today_rides, b.today_fare, b.week_rides, b.week_fare, b.month_rides, b.month_fare,
	       p.drivers, p.rides, p.amount
	FROM d, b, p`

// Stats reads the dashboard's counts at q. Commission, the clock and who is
// on duty are the service's to fill in.
func (r *StatsRepository) Stats(ctx context.Context, q StatsQuery) (domain.AdminStats, error) {
	var (
		st     domain.AdminStats
		bk     = &st.BookingsByStatus
		kyc    = &st.DriversByKYC
		rides  = &st.CompletedRides
		payout = &st.PayoutsDue
	)
	err := r.db.QueryRow(ctx, statsSQL, q.ClosesBefore, q.Today, q.Last7Days, q.Last30Days, q.Now).Scan(
		&st.Users.Customers,
		&st.Users.Drivers, &kyc.Incomplete, &kyc.Submitted, &kyc.Verified, &kyc.Rejected,
		&bk.Open, &bk.Accepted, &bk.InProgress, &bk.Completed, &bk.Cancelled, &bk.Expired, &bk.Total,
		&rides.Today.Rides, &rides.Today.GrossFarePaise,
		&rides.Last7Days.Rides, &rides.Last7Days.GrossFarePaise,
		&rides.Last30Days.Rides, &rides.Last30Days.GrossFarePaise,
		&payout.Drivers, &payout.Rides, &payout.AmountPaise,
	)
	if err != nil {
		return domain.AdminStats{}, fmt.Errorf("reading stats: %w", err)
	}
	return st, nil
}
