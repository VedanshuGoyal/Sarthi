package service

import (
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

func TestSharesLocation(t *testing.T) {
	start := time.Date(2026, 10, 26, 10, 0, 0, 0, ist)
	for _, tc := range []struct {
		status domain.RideStatus
		now    time.Time
		want   bool
	}{
		{domain.RideStatusAccepted, start.Add(-trackingLead - time.Second), false},
		{domain.RideStatusAccepted, start.Add(-trackingLead), true},
		{domain.RideStatusAccepted, start.Add(time.Hour), true}, // running late
		{domain.RideStatusArrived, start.Add(-3 * time.Hour), true},
		{domain.RideStatusInProgress, start.Add(5 * time.Hour), true},
		{domain.RideStatusRequested, start, false},
		{domain.RideStatusCompleted, start, false},
		{domain.RideStatusCancelled, start, false},
	} {
		if got := sharesLocation(tc.status, start, tc.now); got != tc.want {
			t.Errorf("%s at %s: %v, want %v", tc.status, tc.now.Sub(start), got, tc.want)
		}
	}
}
