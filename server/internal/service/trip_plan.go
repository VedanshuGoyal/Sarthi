package service

import (
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/pkg/geo"
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
	return int64(hourlyTariffRupees(hours, p.luxury())) * 100, true
}

// Bounds on what a customer may book, checked by [tripPlan.checkBookable].
const (
	// maxHireHours caps a round trip's hire. The app offers 1 to 12; the
	// extra room is headroom for a later app, not a price risk, since the
	// fare is still checked against the tariff.
	maxHireHours = 24

	// maxStraightLineMetresPerMinute is the fastest a car is assumed to cover
	// the straight-line distance between two points: 100 km/h (my estimate —
	// roads are longer than the straight line, so real trips are slower).
	// It sets the shortest drive time a booking may claim.
	maxStraightLineMetresPerMinute = 100_000.0 / 60
)

// Late-night surcharge, the customer app's nightSurchargeFor: from 22:00 IST,
// a flat ₹50 plus ₹24 for each hire-hour (or part) driven after it.
const (
	nightFromHour     = 22
	nightFlatRupees   = 50
	nightHourlyRupees = 24
)

var (
	// ErrFareMismatch is returned when a round trip's quoted fare isn't the
	// tariff for its hours, car and start time.
	ErrFareMismatch = errors.New("the fare doesn't match the current tariff for this trip; update the app and try again")

	// ErrTripTooShort is returned when a one-way or multi-stop trip claims
	// less time than the distance needs.
	ErrTripTooShort = errors.New("the trip time is too short for the distance; allow more time and try again")
)

// checkBookable verifies that p prices the trip the way the server would, so
// a customer can't set their own fare. A round trip must quote exactly the
// tariff (base plus night surcharge) for its hours; with no quote, the
// tariff becomes the quote. A one-way trip's drive time, and a multi-stop
// trip's last leave-by, can't be shorter than the straight-line distance
// needs at [maxStraightLineMetresPerMinute].
//
// Only new bookings are checked: stored ones are read with parseTripPlan as
// they were accepted.
func (p *tripPlan) checkBookable(tripType string) error {
	switch tripType {
	case TripRoundTrip:
		if p.Hours < 1 || p.Hours > maxHireHours {
			return fmt.Errorf("%w: hire a driver for 1 to %d hours", ErrInvalidBooking, maxHireHours)
		}
		want := int64(roundTripFareRupees(p.ScheduledAt, p.Hours, p.luxury())) * 100
		if p.QuotedFarePaise != 0 && p.QuotedFarePaise != want {
			return ErrFareMismatch
		}
		p.QuotedFarePaise = want
	case TripOneWay:
		d := p.Destination
		metres := geo.HaversineMeters(p.Pickup.Lat, p.Pickup.Lng, d.Lat, d.Lng)
		if p.EstimatedMinutes < 0 || float64(p.EstimatedMinutes) < metres/maxStraightLineMetresPerMinute {
			return ErrTripTooShort
		}
	case TripMultiStop:
		from, prev, metres := p.Pickup, p.ScheduledAt, 0.0
		for _, s := range p.Stops {
			if s.DepartBy == nil {
				return fmt.Errorf("%w: every stop needs a leave-by time", ErrInvalidBooking)
			}
			if !s.DepartBy.After(prev) {
				return fmt.Errorf("%w: each leave-by time must come after the one before", ErrInvalidBooking)
			}
			metres += geo.HaversineMeters(from.Lat, from.Lng, s.Place.Lat, s.Place.Lng)
			from, prev = s.Place, *s.DepartBy
		}
		if prev.Sub(p.ScheduledAt).Minutes() < metres/maxStraightLineMetresPerMinute {
			return ErrTripTooShort
		}
	}
	return nil
}

// completeCar reports whether car names a plate, a car type and a gearbox
// the server knows — what drivers are matched (gearbox) and the trip priced
// (luxury or not) by.
func completeCar(car *domain.RideCar) bool {
	return car != nil && validRegistration(normalizeRegistration(car.Registration)) &&
		validCarType(domain.CarType(car.CarType)) && validTransmission(domain.CarTransmission(car.Transmission))
}

// luxury reports whether the trip is priced on the luxury tariff.
func (p tripPlan) luxury() bool {
	return p.Car != nil && p.Car.CarType == string(domain.CarTypeLuxury)
}

// roundTripFareRupees is the fare the customer app quotes for a round trip:
// the hourly tariff plus the late-night surcharge.
func roundTripFareRupees(start time.Time, hours int, luxury bool) int {
	return hourlyTariffRupees(hours, luxury) + nightSurchargeRupees(start, hours)
}

// overtimeGrace is how far past its booked hours a trip may run before the
// extra time is charged (my pick; the owner decided overtime is charged).
const overtimeGrace = 15 * time.Minute

// billedHours is the hours a trip's booked fare pays for: a round trip's
// hired hours, or the others' duration rounded up, as [tripPlan.Fare]
// estimates them.
func (p tripPlan) billedHours() int {
	if p.Hours > 0 {
		return p.Hours
	}
	return int(math.Ceil(p.Duration().Hours()))
}

// hourlyCharge is the hourly tariff, with the night surcharge, for a trip
// from started to ended: each started hour counts as a whole one, at least
// one.
func hourlyCharge(p tripPlan, started, ended time.Time) int64 {
	minutes := max(int(ended.Sub(started)/time.Minute), 0)
	hours := min(max((minutes+59)/60, 1), maxHireHours)
	return int64(roundTripFareRupees(started, hours, p.luxury())) * 100
}

// finalFare is what a trip that ran from started to ended costs, booked
// being its fare as booked:
//
//   - run past its booked hours plus overtimeGrace: the hourly charge for
//     the time used, never less than booked — extra time is billed;
//   - otherwise, ended early by the customer: the hourly charge for the time
//     used, never more than booked;
//   - otherwise (the driver completed it within its time): as booked.
//
// One-way and multi-stop trips are charged the same way: their fares are
// hourly estimates too.
func finalFare(p tripPlan, booked int64, started, ended time.Time, byCustomer bool) int64 {
	charge := hourlyCharge(p, started, ended)
	if ended.Sub(started) > time.Duration(p.billedHours())*time.Hour+overtimeGrace {
		return max(charge, booked)
	}
	if byCustomer {
		return min(charge, booked)
	}
	return booked
}

// nightSurchargeRupees is the customer app's nightSurchargeFor: nothing
// unless some of the hire runs at or after 22:00 IST on the start's day;
// then a flat fee plus a rate per night hour, a part hour counting as whole.
// A ride that starts after 22:00 is night for its whole length.
func nightSurchargeRupees(start time.Time, hours int) int {
	s := start.In(ist)
	finish := s.Add(time.Duration(hours) * time.Hour)
	nightStart := time.Date(s.Year(), s.Month(), s.Day(), nightFromHour, 0, 0, 0, ist)
	if s.After(nightStart) {
		nightStart = s
	}
	if !finish.After(nightStart) {
		return 0
	}
	minutes := int(finish.Sub(nightStart) / time.Minute)
	nightHours := (minutes + 59) / 60
	if nightHours == 0 {
		return 0
	}
	return nightFlatRupees + nightHourlyRupees*nightHours
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
