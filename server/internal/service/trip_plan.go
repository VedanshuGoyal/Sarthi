package service

import (
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// Trip types the customer app books.
const (
	TripRoundTrip = "roundTrip"
	TripOneWay    = "oneWay"
	TripMultiStop = "multiStop"
)

// ist is India Standard Time. The customer app sends wall-clock times with no
// offset, and IST has no daylight saving, so a fixed zone is exact and needs
// no tzdata on the host.
var ist = time.FixedZone("IST", 5*60*60+30*60)

// errBadTrip is returned when a booking's details can't be read as its trip
// type. Wrapped with the offending field.
var errBadTrip = errors.New("unreadable trip details")

// tripPlan is a booking's schemaless details read into typed fields: where
// the driver starts, where they go, when, for how long, and in which car.
type tripPlan struct {
	ScheduledAt      time.Time
	Pickup           domain.RidePlace
	Destination      *domain.RidePlace
	Stops            []domain.RideStop
	Hours            int
	EstimatedMinutes int
	Car              *domain.RideCar

	// QuotedFarePaise is the fare the customer was shown, when the trip type
	// quotes one (round trips). Zero otherwise.
	QuotedFarePaise int64
}

// parseTripPlan reads the details the customer app sent for tripType. The
// shapes mirror the app's RoundTripBooking, OneWayTrip and MultiStopTrip
// toJson — see apps/user_app/lib/features/ride/domain.
func parseTripPlan(tripType string, d map[string]any) (tripPlan, error) {
	var p tripPlan
	at, err := parseWallTime(str(d, "scheduledAt"))
	if err != nil {
		return tripPlan{}, fmt.Errorf("%w: scheduledAt: %v", errBadTrip, err)
	}
	p.ScheduledAt = at
	p.Car = parseCar(d["car"])

	switch tripType {
	case TripRoundTrip:
		p.Pickup, err = parsePlace(d["pickup"])
		p.Hours = int(num(d, "hours"))
		if fare := num(d, "fare"); fare > 0 {
			p.QuotedFarePaise = int64(math.Round(fare * 100))
		}
	case TripOneWay:
		p.Pickup, err = parsePlace(d["start"])
		if err == nil {
			var dest domain.RidePlace
			dest, err = parsePlace(d["destination"])
			p.Destination = &dest
		}
		p.EstimatedMinutes = int(num(d, "estimatedTravelMinutes"))
	case TripMultiStop:
		p.Pickup, err = parsePlace(d["start"])
		stops, _ := d["stops"].([]any)
		for _, raw := range stops {
			m, _ := raw.(map[string]any)
			place, perr := parsePlace(m["location"])
			if perr != nil {
				err = perr
				break
			}
			stop := domain.RideStop{Place: place, Task: str(m, "task")}
			if t, terr := parseWallTime(str(m, "departBy")); terr == nil {
				stop.DepartBy = &t
			}
			p.Stops = append(p.Stops, stop)
		}
		if err == nil && len(p.Stops) == 0 {
			err = errors.New("no stops")
		}
	default:
		return tripPlan{}, fmt.Errorf("%w: unknown trip type %q", errBadTrip, tripType)
	}
	if err != nil {
		return tripPlan{}, fmt.Errorf("%w: %v", errBadTrip, err)
	}
	return p, nil
}

// Duration is how long the driver is booked for: the hired hours of a round
// trip, the predicted drive of a one-way trip, or until the last stop's
// leave-by time on a multi-stop trip. Never less than an hour.
func (p tripPlan) Duration() time.Duration {
	var d time.Duration
	switch {
	case p.Hours > 0:
		d = time.Duration(p.Hours) * time.Hour
	case p.EstimatedMinutes > 0:
		d = time.Duration(p.EstimatedMinutes) * time.Minute
	case len(p.Stops) > 0 && p.Stops[len(p.Stops)-1].DepartBy != nil:
		d = p.Stops[len(p.Stops)-1].DepartBy.Sub(p.ScheduledAt)
	}
	return max(d, time.Hour)
}

// EndsAt is when the driver should be free again.
func (p tripPlan) EndsAt() time.Time { return p.ScheduledAt.Add(p.Duration()) }

// Fare returns the fare in paise and whether it was estimated. A quoted fare
// is used as is; otherwise the trip is priced on the round-trip hourly tariff
// for its [tripPlan.Duration], rounded up to whole hours.
//
// The estimate is a stand-in until one-way and multi-stop trips get their
// own rate cards — it mirrors the customer app's RoundTripTariff so drivers
// see the same rupee figures the customer would for that many hours.
func (p tripPlan) Fare() (paise int64, estimated bool) {
	if p.QuotedFarePaise > 0 {
		return p.QuotedFarePaise, false
	}
	hours := int(math.Ceil(p.Duration().Hours()))
	luxury := p.Car != nil && p.Car.CarType == string(domain.CarTypeLuxury)
	return int64(hourlyTariffRupees(hours, luxury)) * 100, true
}

// hourlyTariffRupees is the customer app's RoundTripTariff.fareFor: flat
// blocks for the first and second hour, then a flat rate per extra hour.
// Standard: 139 / 240 / +100. Luxury: 196 / 330 / +110.
func hourlyTariffRupees(hours int, luxury bool) int {
	first, second, extra := 139, 240, 100
	if luxury {
		first, second, extra = 196, 330, 110
	}
	switch {
	case hours <= 1:
		return first
	case hours == 2:
		return second
	default:
		return second + (hours-2)*extra
	}
}

// parseWallTime reads an ISO-8601 time. One with an offset (or Z) is taken as
// given; one without is a wall-clock time in IST, which is what Dart's
// DateTime.toIso8601String produces for a local time on an Indian phone.
func parseWallTime(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, errors.New("missing")
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t, nil
	}
	return time.ParseInLocation("2006-01-02T15:04:05.999999999", s, ist)
}

// parsePlace reads the app's PickupLocation: {address, point: {latitude,
// longitude}}.
func parsePlace(raw any) (domain.RidePlace, error) {
	m, ok := raw.(map[string]any)
	if !ok {
		return domain.RidePlace{}, errors.New("missing place")
	}
	point, _ := m["point"].(map[string]any)
	lat, latOK := point["latitude"].(float64)
	lng, lngOK := point["longitude"].(float64)
	if !latOK || !lngOK {
		return domain.RidePlace{}, errors.New("place without coordinates")
	}
	return domain.RidePlace{Address: str(m, "address"), Lat: lat, Lng: lng}, nil
}

// parseCar reads the app's Car, or nil when the trip names none.
func parseCar(raw any) *domain.RideCar {
	m, ok := raw.(map[string]any)
	if !ok {
		return nil
	}
	return &domain.RideCar{
		Registration: str(m, "registration"),
		CarType:      str(m, "carType"),
		Transmission: str(m, "transmission"),
	}
}

func str(m map[string]any, key string) string {
	s, _ := m[key].(string)
	return s
}

// num reads a JSON number. encoding/json and pgx's JSONB decoding both yield
// float64 for numbers in a map[string]any.
func num(m map[string]any, key string) float64 {
	f, _ := m[key].(float64)
	return f
}
