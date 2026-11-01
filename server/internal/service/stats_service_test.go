package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// statsSpy returns st (or err) and remembers the query it was asked.
type statsSpy struct {
	st  domain.AdminStats
	err error
	got repository.StatsQuery
}

func (s *statsSpy) Stats(_ context.Context, q repository.StatsQuery) (domain.AdminStats, error) {
	s.got = q
	return s.st, s.err
}

type onDutyCount int

func (n onDutyCount) Count() int { return int(n) }

func TestStats_istWindows(t *testing.T) {
	store := &statsSpy{}
	svc := NewStatsService(store, nil, 1300)
	// 1 Nov 2026, 01:00 IST — still 31 Oct in UTC.
	now := time.Date(2026, 10, 31, 19, 30, 0, 0, time.UTC)
	svc.now = func() time.Time { return now }

	st, err := svc.Stats(context.Background())
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	q := store.got
	checks := []struct {
		name      string
		got, want time.Time
	}{
		{"today", q.Today, time.Date(2026, 11, 1, 0, 0, 0, 0, ist)},
		{"last 7 days", q.Last7Days, time.Date(2026, 10, 26, 0, 0, 0, 0, ist)},
		{"last 30 days", q.Last30Days, time.Date(2026, 10, 3, 0, 0, 0, 0, ist)},
		{"now", q.Now, now},
		{"closes before", q.ClosesBefore, now.Add(30 * time.Minute)},
		{"today.from", st.CompletedRides.Today.From, time.Date(2026, 11, 1, 0, 0, 0, 0, ist)},
		{"last7Days.from", st.CompletedRides.Last7Days.From, time.Date(2026, 10, 26, 0, 0, 0, 0, ist)},
		{"last30Days.from", st.CompletedRides.Last30Days.From, time.Date(2026, 10, 3, 0, 0, 0, 0, ist)},
		{"asOf", st.AsOf, now},
	}
	for _, c := range checks {
		if !c.got.Equal(c.want) {
			t.Errorf("%s = %v, want %v", c.name, c.got, c.want)
		}
	}
	if _, off := st.AsOf.Zone(); off != 5*3600+1800 {
		t.Errorf("asOf offset = %ds, want IST (+05:30)", off)
	}
}

func TestStats_expiredMatchesListMine(t *testing.T) {
	store := &statsSpy{}
	svc := NewStatsService(store, nil, 1300)
	now := time.Date(2026, 11, 1, 12, 0, 0, 0, ist)
	svc.now = func() time.Time { return now }
	if _, err := svc.Stats(context.Background()); err != nil {
		t.Fatalf("Stats: %v", err)
	}
	// The SQL counts a requested ride as expired when scheduled_at <
	// ClosesBefore; ListMine when closedToDrivers. They must agree.
	cut := store.got.ClosesBefore
	if !closedToDrivers(cut.Add(-time.Nanosecond), now) {
		t.Errorf("a ride starting just before ClosesBefore should be closed to drivers")
	}
	if closedToDrivers(cut, now) {
		t.Errorf("a ride starting at ClosesBefore should still be open")
	}
}

func TestStats_commissionAtRate(t *testing.T) {
	for _, tc := range []struct {
		bp          int64
		wantPercent float64
		wantPaise   int64
	}{
		{1300, 13, 1605},   // 1604.85
		{1250, 12.5, 1543}, // 1543.125
		{0, 0, 0},
	} {
		store := &statsSpy{st: domain.AdminStats{CompletedRides: domain.StatsCompletedRides{
			Today:      domain.StatsRideWindow{Rides: 1, GrossFarePaise: 12345},
			Last7Days:  domain.StatsRideWindow{Rides: 2, GrossFarePaise: 24690},
			Last30Days: domain.StatsRideWindow{Rides: 0, GrossFarePaise: 0},
		}}}
		st, err := NewStatsService(store, nil, tc.bp).Stats(context.Background())
		if err != nil {
			t.Fatalf("Stats: %v", err)
		}
		if st.CommissionPercent != tc.wantPercent {
			t.Errorf("bp %d: commissionPercent = %v, want %v", tc.bp, st.CommissionPercent, tc.wantPercent)
		}
		if got := st.CompletedRides.Today.CommissionPaise; got != tc.wantPaise {
			t.Errorf("bp %d: today commission = %d, want %d", tc.bp, got, tc.wantPaise)
		}
		if got, want := st.CompletedRides.Last7Days.CommissionPaise, (24690*tc.bp+5000)/10000; got != want {
			t.Errorf("bp %d: 7-day commission = %d, want %d", tc.bp, got, want)
		}
		if got := st.CompletedRides.Last30Days.CommissionPaise; got != 0 {
			t.Errorf("bp %d: 30-day commission on nothing = %d, want 0", tc.bp, got)
		}
		if st.CompletedRides.Today.Rides != 1 || st.CompletedRides.Today.GrossFarePaise != 12345 {
			t.Errorf("bp %d: store's counts not passed through: %+v", tc.bp, st.CompletedRides.Today)
		}
	}
}

func TestStats_commissionMatchesPayments(t *testing.T) {
	for _, bp := range []int64{0, 1, 999, 1250, 1300, 1500, 10000} {
		pay := &PaymentService{commissionBP: bp}
		for _, amount := range []int64{0, 1, 49, 50, 99, 100, 12345, 13900, 99999, 1_000_000_007} {
			if got, want := commissionOn(amount, bp), pay.commission(amount); got != want {
				t.Errorf("commissionOn(%d, %d) = %d, PaymentService.commission = %d", amount, bp, got, want)
			}
		}
	}
}

func TestStats_onDuty(t *testing.T) {
	st, err := NewStatsService(&statsSpy{}, onDutyCount(3), 1300).Stats(context.Background())
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	if st.DriversOnDuty == nil || *st.DriversOnDuty != 3 {
		t.Errorf("driversOnDuty = %v, want 3", st.DriversOnDuty)
	}

	st, err = NewStatsService(&statsSpy{}, nil, 1300).Stats(context.Background())
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	if st.DriversOnDuty != nil {
		t.Errorf("driversOnDuty = %d with no presence index, want nil", *st.DriversOnDuty)
	}
}

func TestStats_storeError(t *testing.T) {
	boom := errors.New("db down")
	_, err := NewStatsService(&statsSpy{err: boom}, onDutyCount(1), 1300).Stats(context.Background())
	if !errors.Is(err, boom) {
		t.Errorf("err = %v, want %v", err, boom)
	}
}
