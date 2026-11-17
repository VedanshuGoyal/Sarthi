package service

import (
	"math"
	"regexp"
	"strings"

	"github.com/sarthi/server/internal/domain"
)

// coarseDecimals is how many decimal places a place's coordinates keep
// before a driver accepts the ride: two, about 1.1 km north–south and 1 km
// east–west in Delhi NCR — enough to judge the trip, not to find the house.
const coarseDecimals = 2

// coarsePlace is p as drivers see it before accepting: the locality instead
// of the address, and coordinates rounded to coarseDecimals.
func coarsePlace(p domain.RidePlace) domain.RidePlace {
	scale := math.Pow(10, coarseDecimals)
	return domain.RidePlace{
		Address: localityOf(p.Address),
		Lat:     math.Round(p.Lat*scale) / scale,
		Lng:     math.Round(p.Lng*scale) / scale,
	}
}

// coarseRide strips ride of what would locate or identify the customer
// before a driver takes it: every place becomes its locality and rounded
// coordinates, stops lose their errands, and the car its plate. When,
// how long, the gearbox and the fare stay, so the driver can decide.
func coarseRide(ride domain.DriverRide) domain.DriverRide {
	ride.Approximate = true
	ride.Pickup = coarsePlace(ride.Pickup)
	if ride.Destination != nil {
		d := coarsePlace(*ride.Destination)
		ride.Destination = &d
	}
	if len(ride.Stops) > 0 {
		stops := make([]domain.RideStop, len(ride.Stops))
		for i, s := range ride.Stops {
			stops[i] = domain.RideStop{Place: coarsePlace(s.Place), DepartBy: s.DepartBy}
		}
		ride.Stops = stops
	}
	if ride.Car != nil {
		car := *ride.Car
		car.Registration = ""
		ride.Car = &car
	}
	ride.Customer = nil
	return ride
}

var (
	// pinCode is an Indian postal code inside an address part.
	pinCode = regexp.MustCompile(`\b\d{6}\b`)

	// houseLike is an address part that names a building, a flat, a plot or a
	// street rather than an area: it starts with a number ("12", "221B",
	// "B-12", "A/4") or carries one of these words. Words that are also
	// area names in NCR ("Kashmere Gate", "Chandni Chowk", "Safdarjung
	// Enclave") are left out.
	houseLike = regexp.MustCompile(`(?i)^[a-z]{0,2}[-/]?\d|` +
		`\b(house|h\.? ?no|flat|floor|tower|apartments?|apt|block|plot|villa|wing|` +
		`lane|gali|street|road|rd|marg|building|bldg|society|residency)\b|#`)

	// indianStates are the state and union-territory names a geocoded
	// address ends with, before the country.
	indianStates = map[string]bool{
		"andaman and nicobar islands": true, "andhra pradesh": true, "arunachal pradesh": true,
		"assam": true, "bihar": true, "chandigarh": true, "chhattisgarh": true,
		"dadra and nagar haveli and daman and diu": true, "delhi": true, "goa": true,
		"gujarat": true, "haryana": true, "himachal pradesh": true, "jammu and kashmir": true,
		"jharkhand": true, "karnataka": true, "kerala": true, "ladakh": true,
		"lakshadweep": true, "madhya pradesh": true, "maharashtra": true, "manipur": true,
		"meghalaya": true, "mizoram": true, "nagaland": true, "odisha": true,
		"puducherry": true, "punjab": true, "rajasthan": true, "sikkim": true,
		"tamil nadu": true, "telangana": true, "tripura": true, "uttar pradesh": true,
		"uttarakhand": true, "west bengal": true, "nct of delhi": true,
	}
)

// localityOf reduces a full address to its area and city — "B-12, Block B,
// Saket, New Delhi, Delhi 110017, India" to "Saket, New Delhi" — dropping
// the country, state, postal code and anything naming a house or street.
// It returns "" when nothing area-like is left.
func localityOf(address string) string {
	var parts []string
	for _, p := range strings.Split(address, ",") {
		p = strings.Join(strings.Fields(pinCode.ReplaceAllString(p, "")), " ")
		if p != "" {
			parts = append(parts, p)
		}
	}
	if n := len(parts); n > 0 && strings.EqualFold(parts[n-1], "india") {
		parts = parts[:n-1]
	}
	// A trailing state goes, unless it's all there is ("Delhi").
	if n := len(parts); n > 1 && indianStates[strings.ToLower(parts[n-1])] {
		parts = parts[:n-1]
	}
	if len(parts) == 0 {
		return ""
	}
	city := parts[len(parts)-1]
	if houseLike.MatchString(city) {
		return ""
	}
	if len(parts) > 1 {
		if area := parts[len(parts)-2]; !houseLike.MatchString(area) && !strings.EqualFold(area, city) {
			return area + ", " + city
		}
	}
	return city
}
