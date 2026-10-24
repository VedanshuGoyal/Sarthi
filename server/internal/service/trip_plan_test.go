package service

import (
	"errors"
	"testing"
	"time"
)

func place(addr string, lat, lng float64) map[string]any {
	return map[string]any{
		"address": addr,
		"point":   map[string]any{"latitude": lat, "longitude": lng},
	}
}

func TestParseTripPlan_oneWay(t *testing.T) {
	p, err := parseTripPlan(TripOneWay, map[string]any{
		"start":                  place("A", 28.6, 77.2),
		"destination":            place("B", 28.5, 77.1),
		"scheduledAt":            "2026-10-25T09:00:00.000Z",
		"estimatedTravelMinutes": 150.0,
		"car":                    map[string]any{"registration": "X", "carType": "suv", "transmission": "manual"},
	})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if p.Destination == nil || p.Destination.Address != "B" {
		t.Errorf("destination = %+v, want B", p.Destination)
	}
	if want := time.Date(2026, 10, 25, 9, 0, 0, 0, time.UTC); !p.ScheduledAt.Equal(want) {
		t.Errorf("scheduledAt = %v, want %v (offset taken as given)", p.ScheduledAt, want)
	}
	// 150 minutes rounds up to 3 hours on the standard tariff: 240 + 100.
	fare, estimated := p.Fare()
	if fare != 34000 || !estimated {
		t.Errorf("fare = %d (estimated %v), want estimated 34000", fare, estimated)
	}
}

func TestParseTripPlan_multiStop(t *testing.T) {
	p, err := parseTripPlan(TripMultiStop, map[string]any{
		"start":       place("Home", 28.6, 77.2),
		"scheduledAt": "2026-10-25T10:00:00.000",
		"stops": []any{
			map[string]any{"location": place("Bank", 28.61, 77.21), "task": "Deposit", "departBy": "2026-10-25T10:40:00.000"},
			map[string]any{"location": place("Mall", 28.62, 77.22), "task": "Shop", "departBy": "2026-10-25T11:30:00.000"},
		},
	})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(p.Stops) != 2 || p.Stops[1].Task != "Shop" {
		t.Fatalf("stops = %+v", p.Stops)
	}
	if got := p.Duration(); got != 90*time.Minute {
		t.Errorf("duration = %v, want 1h30m (until the last stop's leave-by)", got)
	}
	// No car named: standard tariff, 2 hours.
	if fare, _ := p.Fare(); fare != 24000 {
		t.Errorf("fare = %d, want 24000", fare)
	}
}

func TestParseTripPlan_luxuryEstimate(t *testing.T) {
	p, err := parseTripPlan(TripOneWay, map[string]any{
		"start":                  place("A", 1, 1),
		"destination":            place("B", 2, 2),
		"scheduledAt":            "2026-10-25T09:00:00.000",
		"estimatedTravelMinutes": 20.0,
		"car":                    map[string]any{"carType": "luxury", "transmission": "automatic"},
	})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	// Short trips still book a full hour.
	if got := p.Duration(); got != time.Hour {
		t.Errorf("duration = %v, want 1h minimum", got)
	}
	if fare, _ := p.Fare(); fare != 19600 {
		t.Errorf("fare = %d, want luxury first hour 19600", fare)
	}
}

func TestParseTripPlan_rejectsUnreadable(t *testing.T) {
	cases := map[string]struct {
		tripType string
		details  map[string]any
	}{
		"no time":       {TripRoundTrip, map[string]any{"pickup": place("A", 1, 1)}},
		"no pickup":     {TripRoundTrip, map[string]any{"scheduledAt": "2026-10-25T09:00:00"}},
		"no stops":      {TripMultiStop, map[string]any{"start": place("A", 1, 1), "scheduledAt": "2026-10-25T09:00:00"}},
		"unknown type":  {"teleport", map[string]any{"scheduledAt": "2026-10-25T09:00:00"}},
		"no dest":       {TripOneWay, map[string]any{"start": place("A", 1, 1), "scheduledAt": "2026-10-25T09:00:00"}},
		"bad timestamp": {TripRoundTrip, map[string]any{"pickup": place("A", 1, 1), "scheduledAt": "tomorrow"}},
	}
	for name, c := range cases {
		if _, err := parseTripPlan(c.tripType, c.details); !errors.Is(err, errBadTrip) {
			t.Errorf("%s: err = %v, want errBadTrip", name, err)
		}
	}
}

func TestHourlyTariffRupees(t *testing.T) {
	cases := []struct {
		hours  int
		luxury bool
		want   int
	}{
		{0, false, 139}, {1, false, 139}, {2, false, 240}, {5, false, 540},
		{1, true, 196}, {2, true, 330}, {4, true, 550},
	}
	for _, c := range cases {
		if got := hourlyTariffRupees(c.hours, c.luxury); got != c.want {
			t.Errorf("hourlyTariffRupees(%d, %v) = %d, want %d", c.hours, c.luxury, got, c.want)
		}
	}
}
