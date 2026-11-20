package service

import (
	"context"
	"errors"
	"testing"

	"github.com/sarthi/server/internal/domain"
)

// multiStopDetails is a multi-stop payload as the customer app sends it,
// starting two hours after bookingTestNow, with car when it isn't nil.
func multiStopDetails(car map[string]any) map[string]any {
	place := func(address string, lat, lng float64) map[string]any {
		return map[string]any{"address": address, "point": map[string]any{"latitude": lat, "longitude": lng}}
	}
	d := map[string]any{
		"start":       place("Connaught Place, New Delhi", 28.6315, 77.2167),
		"scheduledAt": "2026-10-24T13:30:00.000",
		"stops": []any{
			map[string]any{"location": place("Lajpat Nagar", 28.5677, 77.2433), "task": "Collect the refill",
				"departBy": "2026-10-24T15:00:00.000"},
			map[string]any{"location": place("Bhikaji Cama Place", 28.5679, 77.1859), "task": "Drop the forms",
				"departBy": "2026-10-24T17:00:00.000"},
		},
	}
	if car != nil {
		d["car"] = car
	}
	return d
}

func testCar(carType, transmission string) map[string]any {
	return map[string]any{"id": "c1", "registration": "DL01AB1234", "carType": carType, "transmission": transmission}
}

// The released apps (1.6.0 and before) never send a car with a multi-stop
// trip: it is still booked, priced on the standard tariff and open to any
// driver.
func TestBookingService_Record_multiStopWithoutACarFromOlderApps(t *testing.T) {
	store := &fakeBookingStore{}
	if _, _, err := newTestBookingService(store).Record(context.Background(), "u1", TripMultiStop,
		multiStopDetails(nil), "", false); err != nil || !store.insertHit {
		t.Fatalf("Record: %v (stored %v), want the booking stored", err, store.insertHit)
	}
	// 13:30 to 17:00 is 3.5 h: billed as 4 h on the standard tariff.
	if store.params.FarePaise != 44000 || !store.params.FareEstimated {
		t.Errorf("fare = %d (estimated %v), want an estimated 44000", store.params.FarePaise, store.params.FareEstimated)
	}
	plan, err := parseTripPlan(TripMultiStop, store.params.Details)
	if err != nil || plan.Car != nil {
		t.Fatalf("plan car = %+v, %v; want none", plan.Car, err)
	}
	for _, d := range []domain.DriverTransmission{domain.DriverTransmissionManual, domain.DriverTransmissionAutomatic} {
		if !canDrive(d, plan.Car) {
			t.Errorf("a %s driver can't take a multi-stop with no car", d)
		}
	}
}

// An app that asks for the car on every trip type must send one — a whole
// one — with every booking, multi-stop included.
func TestBookingService_Record_carRequiredFromAppsThatAskForIt(t *testing.T) {
	roundTripNoCar := roundTripDetails()
	delete(roundTripNoCar, "car")
	for _, tc := range []struct {
		name     string
		tripType string
		details  map[string]any
		wantErr  error
	}{
		{"multi-stop, no car", TripMultiStop, multiStopDetails(nil), ErrCarRequired},
		{"multi-stop, no gearbox", TripMultiStop, multiStopDetails(testCar("sedan", "")), ErrCarRequired},
		{"multi-stop, unknown car type", TripMultiStop, multiStopDetails(testCar("tractor", "manual")), ErrCarRequired},
		{"multi-stop, no plate", TripMultiStop, multiStopDetails(map[string]any{"carType": "sedan", "transmission": "manual"}), ErrCarRequired},
		{"multi-stop, empty car", TripMultiStop, multiStopDetails(map[string]any{}), ErrCarRequired},
		{"multi-stop with a car", TripMultiStop, multiStopDetails(testCar("sedan", "manual")), nil},
		{"round trip with a car", TripRoundTrip, roundTripDetails(), nil},
		{"round trip, no car", TripRoundTrip, roundTripNoCar, ErrCarRequired},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &fakeBookingStore{}
			_, _, err := newTestBookingService(store).Record(context.Background(), "u1", tc.tripType, tc.details, "", true)
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("err = %v, want %v", err, tc.wantErr)
			}
			if stored := store.insertHit; stored != (tc.wantErr == nil) {
				t.Errorf("stored = %v, want %v", stored, tc.wantErr == nil)
			}
		})
	}
}

// A multi-stop trip that names a car is matched on its gearbox, like the
// other trip types, and a luxury car is priced on the luxury tariff.
func TestBookingService_Record_multiStopCarDecidesGearboxAndTariff(t *testing.T) {
	store := &fakeBookingStore{}
	svc := newTestBookingService(store)
	if _, _, err := svc.Record(context.Background(), "u1", TripMultiStop,
		multiStopDetails(testCar("luxury", "manual")), "", true); err != nil {
		t.Fatalf("Record: %v", err)
	}
	// 4 h on the luxury tariff: 330 + 2 × 110.
	if store.params.FarePaise != 55000 || !store.params.FareEstimated {
		t.Errorf("fare = %d (estimated %v), want an estimated 55000", store.params.FarePaise, store.params.FareEstimated)
	}
	plan, err := parseTripPlan(TripMultiStop, store.params.Details)
	if err != nil || plan.Car == nil || plan.Car.Transmission != "manual" {
		t.Fatalf("plan car = %+v, %v; want the manual car", plan.Car, err)
	}
	for d, want := range map[domain.DriverTransmission]bool{
		domain.DriverTransmissionManual:    true,
		domain.DriverTransmissionBoth:      true,
		domain.DriverTransmissionAutomatic: false,
	} {
		if got := canDrive(d, plan.Car); got != want {
			t.Errorf("canDrive(%s, manual car) = %v, want %v", d, got, want)
		}
	}
}
