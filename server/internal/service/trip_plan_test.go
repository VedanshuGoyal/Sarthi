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

// HUMAN REVIEW REQUIRED: payments. One-way and multi-stop trips are always
// priced by the server: a "fare" slipped into their details is ignored, not
// stored as the ride's fare. (The app shows no fare for them before
// booking; it shows the server's estimate afterwards.)
func TestParseTripPlan_ignoresAClientFareOffRoundTrips(t *testing.T) {
	for _, tc := range []struct {
		tripType string
		details  map[string]any
		want     int64
	}{
		{TripOneWay, map[string]any{
			"start": place("A", 28.6, 77.2), "destination": place("B", 28.5, 77.1),
			"scheduledAt": "2026-10-25T09:00:00.000", "estimatedTravelMinutes": 150.0, "fare": 1.0,
		}, 34000},
		{TripMultiStop, map[string]any{
			"start": place("Home", 28.6, 77.2), "scheduledAt": "2026-10-25T10:00:00.000", "fare": 1.0,
			"stops": []any{map[string]any{"location": place("Bank", 28.61, 77.21), "departBy": "2026-10-25T11:30:00.000"}},
		}, 24000},
	} {
		p, err := parseTripPlan(tc.tripType, tc.details)
		if err != nil {
			t.Fatalf("%s: parse: %v", tc.tripType, err)
		}
		if err := p.checkBookable(tc.tripType); err != nil {
			t.Fatalf("%s: checkBookable: %v", tc.tripType, err)
		}
		if fare, estimated := p.Fare(); fare != tc.want || !estimated {
			t.Errorf("%s: fare = %d (estimated %v), want the server's estimate %d", tc.tripType, fare, estimated, tc.want)
		}
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

// TestRoundTripFareRupees mirrors the customer app's own fare tests
// (booking_details_view_model_test.dart), so the server prices exactly what
// the app quotes.
func TestRoundTripFareRupees(t *testing.T) {
	at := func(hour int) time.Time { return time.Date(2026, 7, 18, hour, 0, 0, 0, ist) }
	cases := []struct {
		name   string
		start  time.Time
		hours  int
		luxury bool
		want   int
	}{
		{"midday, no surcharge", at(12), 3, false, 340},
		{"8pm for 3h: one night hour", at(20), 3, false, 340 + 74},
		{"11pm for 2h: two night hours", at(23), 2, false, 240 + 98},
		{"8pm for 2h ends at 10pm: none", at(20), 2, false, 240},
		{"luxury 9pm for 3h: two night hours", at(21), 3, true, 440 + 98},
		{"small hours start: no evening 10pm", at(1), 2, false, 240},
	}
	for _, c := range cases {
		if got := roundTripFareRupees(c.start, c.hours, c.luxury); got != c.want {
			t.Errorf("%s: fare = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestTripPlan_checkBookable(t *testing.T) {
	sedan := map[string]any{"registration": "X", "carType": "sedan", "transmission": "manual"}
	roundTrip := func(hours, fare float64) map[string]any {
		d := map[string]any{
			"pickup": place("A", 28.6, 77.2), "hours": hours,
			"scheduledAt": "2026-10-25T20:00:00.000", "car": sedan,
		}
		if fare != 0 {
			d["fare"] = fare
		}
		return d
	}
	// Connaught Place to Jaipur: about 235 km in a straight line.
	oneWay := func(minutes float64) map[string]any {
		return map[string]any{
			"start": place("Delhi", 28.6315, 77.2167), "destination": place("Jaipur", 26.9124, 75.7873),
			"scheduledAt": "2026-10-25T09:00:00.000", "estimatedTravelMinutes": minutes, "car": sedan,
		}
	}
	multiStop := func(lastDepartBy string) map[string]any {
		return map[string]any{
			"start": place("Delhi", 28.6315, 77.2167), "scheduledAt": "2026-10-25T09:00:00.000",
			"stops": []any{
				map[string]any{"location": place("Gurgaon", 28.4595, 77.0266), "task": "Pick up", "departBy": "2026-10-25T10:00:00.000"},
				map[string]any{"location": place("Jaipur", 26.9124, 75.7873), "task": "Drop", "departBy": lastDepartBy},
			},
		}
	}
	cases := []struct {
		name     string
		tripType string
		details  map[string]any
		wantErr  error
		wantFare int64 // paise, round trips only
	}{
		{"app's fare, with night surcharge", TripRoundTrip, roundTrip(3, 414), nil, 41400},
		{"no fare: the tariff is used", TripRoundTrip, roundTrip(3, 0), nil, 41400},
		{"fare without the night surcharge", TripRoundTrip, roundTrip(3, 340), ErrFareMismatch, 0},
		{"tampered low fare", TripRoundTrip, roundTrip(10, 300), ErrFareMismatch, 0},
		{"zero hours", TripRoundTrip, roundTrip(0, 139), ErrInvalidBooking, 0},
		{"negative hours", TripRoundTrip, roundTrip(-3, 139), ErrInvalidBooking, 0},
		{"a day and a half", TripRoundTrip, roundTrip(36, 3640), ErrInvalidBooking, 0},
		{"one-way, real drive time", TripOneWay, oneWay(330), nil, 0},
		{"one-way, 1 minute to Jaipur", TripOneWay, oneWay(1), ErrTripTooShort, 0},
		{"one-way, negative minutes", TripOneWay, oneWay(-5), ErrTripTooShort, 0},
		{"multi-stop, room to get there", TripMultiStop, multiStop("2026-10-25T15:00:00.000"), nil, 0},
		{"multi-stop, Jaipur in 20 minutes", TripMultiStop, multiStop("2026-10-25T10:20:00.000"), ErrTripTooShort, 0},
		{"multi-stop, times out of order", TripMultiStop, multiStop("2026-10-25T09:30:00.000"), ErrInvalidBooking, 0},
	}
	for _, c := range cases {
		p, err := parseTripPlan(c.tripType, c.details)
		if err != nil {
			t.Fatalf("%s: parse: %v", c.name, err)
		}
		err = p.checkBookable(c.tripType)
		if c.wantErr == nil && err != nil {
			t.Errorf("%s: err = %v, want nil", c.name, err)
			continue
		}
		if c.wantErr != nil && !errors.Is(err, c.wantErr) {
			t.Errorf("%s: err = %v, want %v", c.name, err, c.wantErr)
			continue
		}
		if c.wantFare != 0 {
			if fare, estimated := p.Fare(); fare != c.wantFare || estimated {
				t.Errorf("%s: fare = %d (estimated %v), want quoted %d", c.name, fare, estimated, c.wantFare)
			}
		}
	}
}

func TestTripPlan_checkBookable_multiStopNeedsEveryLeaveBy(t *testing.T) {
	p, err := parseTripPlan(TripMultiStop, map[string]any{
		"start": place("Home", 28.6, 77.2), "scheduledAt": "2026-10-25T10:00:00.000",
		"stops": []any{map[string]any{"location": place("Bank", 28.61, 77.21), "task": "Deposit"}},
	})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if err := p.checkBookable(TripMultiStop); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("err = %v, want ErrInvalidBooking for a stop with no leave-by", err)
	}
}
