package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

type fakeStatsStore struct {
	st  domain.AdminStats
	err error
}

func (f fakeStatsStore) Stats(context.Context, repository.StatsQuery) (domain.AdminStats, error) {
	return f.st, f.err
}

type fakeOnDuty int

func (n fakeOnDuty) Count() int { return int(n) }

// statsRouter is the real router with only the stats service wired.
func statsRouter(adminToken string, store service.StatsStore) http.Handler {
	stats := service.NewStatsService(store, fakeOnDuty(2), 1300)
	return NewRouter(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, stats, nil, adminToken)
}

func getStats(h http.Handler, auth string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/admin/stats", nil)
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestAdminStatsRoute_requiresToken(t *testing.T) {
	h := statsRouter("s3cret", fakeStatsStore{})
	for _, auth := range []string{"", "Bearer wrong", "s3cret", "Basic s3cret"} {
		if rec := getStats(h, auth); rec.Code != http.StatusUnauthorized {
			t.Errorf("Authorization %q: status %d, want 401", auth, rec.Code)
		}
	}
	if rec := getStats(statsRouter("", fakeStatsStore{}), "Bearer "); rec.Code != http.StatusNotFound {
		t.Errorf("no ADMIN_TOKEN configured: status %d, want 404", rec.Code)
	}
}

func TestAdminStatsRoute_shape(t *testing.T) {
	store := fakeStatsStore{st: domain.AdminStats{
		Users:        domain.StatsUsers{Customers: 12, Drivers: 5},
		DriversByKYC: domain.StatsKYC{Incomplete: 1, Submitted: 1, Verified: 3, Rejected: 0},
		BookingsByStatus: domain.StatsBookings{
			Open: 2, Accepted: 1, InProgress: 0, Completed: 30, Cancelled: 4, Expired: 6, Total: 43,
		},
		CompletedRides: domain.StatsCompletedRides{
			Today:      domain.StatsRideWindow{Rides: 1, GrossFarePaise: 27800},
			Last7Days:  domain.StatsRideWindow{Rides: 6, GrossFarePaise: 166800},
			Last30Days: domain.StatsRideWindow{Rides: 30, GrossFarePaise: 834000},
		},
		PayoutsDue: domain.StatsPayoutsDue{Drivers: 2, Rides: 3, AmountPaise: 60291},
	}}
	rec := getStats(statsRouter("s3cret", store), "Bearer s3cret")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200: %s", rec.Code, rec.Body)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, want no-store", got)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding %s: %v", rec.Body, err)
	}

	wantNumbers := map[string]float64{
		"commissionPercent":                         13,
		"users.customers":                           12,
		"users.drivers":                             5,
		"driversByKyc.incomplete":                   1,
		"driversByKyc.submitted":                    1,
		"driversByKyc.verified":                     3,
		"driversByKyc.rejected":                     0,
		"driversOnDuty":                             2,
		"bookingsByStatus.open":                     2,
		"bookingsByStatus.accepted":                 1,
		"bookingsByStatus.inProgress":               0,
		"bookingsByStatus.completed":                30,
		"bookingsByStatus.cancelled":                4,
		"bookingsByStatus.expired":                  6,
		"bookingsByStatus.total":                    43,
		"completedRides.today.rides":                1,
		"completedRides.today.grossFarePaise":       27800,
		"completedRides.today.commissionPaise":      3614,
		"completedRides.last7Days.rides":            6,
		"completedRides.last7Days.grossFarePaise":   166800,
		"completedRides.last7Days.commissionPaise":  21684,
		"completedRides.last30Days.rides":           30,
		"completedRides.last30Days.grossFarePaise":  834000,
		"completedRides.last30Days.commissionPaise": 108420,
		"payoutsDue.drivers":                        2,
		"payoutsDue.rides":                          3,
		"payoutsDue.amountPaise":                    60291,
	}
	for path, want := range wantNumbers {
		got, ok := lookup(body, path).(float64)
		if !ok {
			t.Errorf("%s missing or not a number in %s", path, rec.Body)
			continue
		}
		if got != want {
			t.Errorf("%s = %v, want %v", path, got, want)
		}
	}
	for _, path := range []string{"asOf", "completedRides.today.from",
		"completedRides.last7Days.from", "completedRides.last30Days.from"} {
		s, ok := lookup(body, path).(string)
		if !ok || !strings.HasSuffix(s, "+05:30") {
			t.Errorf("%s = %v, want an RFC 3339 time in IST", path, lookup(body, path))
		}
	}
}

func TestAdminStatsRoute_storeError(t *testing.T) {
	rec := getStats(statsRouter("s3cret", fakeStatsStore{err: errors.New("db down")}), "Bearer s3cret")
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status %d, want 500", rec.Code)
	}
	var body struct{ Error string }
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Error != "could not load stats" {
		t.Errorf("error = %q, want %q", body.Error, "could not load stats")
	}
}

// lookup walks a dotted path through decoded JSON objects.
func lookup(v any, path string) any {
	for _, key := range strings.Split(path, ".") {
		m, ok := v.(map[string]any)
		if !ok {
			return nil
		}
		v = m[key]
	}
	return v
}
