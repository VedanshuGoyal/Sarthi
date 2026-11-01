package service

import (
	"context"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// StatsStore reads the dashboard's counts (repository.StatsRepository).
type StatsStore interface {
	Stats(ctx context.Context, q repository.StatsQuery) (domain.AdminStats, error)
}

// OnDutyCounter counts the drivers in the live presence index
// (memstore.DriverTracker).
type OnDutyCounter interface {
	Count() int
}

// StatsService is the ops dashboard's read: counts from PostgreSQL, who is
// on duty from memory, and MOJUD's commission on the window fares.
type StatsService struct {
	store        StatsStore
	onDuty       OnDutyCounter
	commissionBP int64
	now          func() time.Time
}

// NewStatsService wires the service. onDuty nil leaves driversOnDuty out;
// commissionBP is COMMISSION_PERCENT in basis points (1300 = 13%).
func NewStatsService(store StatsStore, onDuty OnDutyCounter, commissionBP int64) *StatsService {
	return &StatsService{store: store, onDuty: onDuty, commissionBP: commissionBP, now: time.Now}
}

// Stats reads the dashboard now. Windows are IST calendar days ending now —
// today, the last 7 (today and the 6 before) and the last 30 — and a
// requested ride counts as expired by the rule ListMine uses.
func (s *StatsService) Stats(ctx context.Context) (domain.AdminStats, error) {
	now := s.now().In(ist)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, ist)
	q := repository.StatsQuery{
		Now:          now,
		ClosesBefore: now.Add(acceptCutoff),
		Today:        today,
		Last7Days:    today.AddDate(0, 0, -6),
		Last30Days:   today.AddDate(0, 0, -29),
	}
	st, err := s.store.Stats(ctx, q)
	if err != nil {
		return domain.AdminStats{}, err
	}
	st.AsOf = now
	st.CommissionPercent = float64(s.commissionBP) / 100
	for _, w := range []struct {
		win  *domain.StatsRideWindow
		from time.Time
	}{
		{&st.CompletedRides.Today, q.Today},
		{&st.CompletedRides.Last7Days, q.Last7Days},
		{&st.CompletedRides.Last30Days, q.Last30Days},
	} {
		w.win.From = w.from
		w.win.CommissionPaise = commissionOn(w.win.GrossFarePaise, s.commissionBP)
	}
	if s.onDuty != nil {
		n := s.onDuty.Count()
		st.DriversOnDuty = &n
	}
	return st, nil
}

// commissionOn is bp basis points of amount, rounded to the nearest paisa —
// the rounding PaymentService.commission applies to each payment.
func commissionOn(amount, bp int64) int64 {
	return (amount*bp + 5000) / 10000
}
