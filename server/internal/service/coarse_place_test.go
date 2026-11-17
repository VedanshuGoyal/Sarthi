package service

import (
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

func TestLocalityOf(t *testing.T) {
	for address, want := range map[string]string{
		"B-12, Block B, Saket, New Delhi, Delhi 110017, India":                       "Saket, New Delhi",
		"Flat 402, Tower 5, DLF Phase 2, Sector 25, Gurugram, Haryana 122002, India": "Sector 25, Gurugram",
		"Connaught Place, New Delhi, Delhi 110001, India":                            "Connaught Place, New Delhi",
		"221B, MG Road, Gurugram":                                                    "Gurugram",
		"Noida, Uttar Pradesh 201301":                                                "Noida",
		"Kashmere Gate, Delhi":                                                       "Kashmere Gate", // a trailing Delhi reads as the state
		"India Gate":                                                                 "India Gate",
		"Delhi":                                                                      "Delhi",
		"12 Rajpath":                                                                 "",
		"House No. 7":                                                                "",
		"  ,  ":                                                                      "",
		"":                                                                           "",
	} {
		if got := localityOf(address); got != want {
			t.Errorf("localityOf(%q) = %q, want %q", address, got, want)
		}
	}
}

func TestCoarseRide_hidesWhatLocatesTheCustomer(t *testing.T) {
	by := testNow.Add(3 * time.Hour)
	ride := domain.DriverRide{
		ID:          "r1",
		Pickup:      domain.RidePlace{Address: "B-12, Block B, Saket, New Delhi, Delhi 110017, India", Lat: 28.52437, Lng: 77.20681},
		Destination: &domain.RidePlace{Address: "Terminal 3, IGI Airport, New Delhi", Lat: 28.5562, Lng: 77.1000},
		Stops: []domain.RideStop{{
			Place: domain.RidePlace{Address: "Gate 2, DPS, Vasant Kunj, New Delhi", Lat: 28.5293, Lng: 77.1530},
			Task:  "Collect Riya from school", DepartBy: &by,
		}},
		Car:       &domain.RideCar{Registration: "DL3CAB1234", CarType: "sedan", Transmission: "manual"},
		Customer:  &domain.RideCustomer{Name: "Asha", PhoneE164: "+919800000000"},
		FarePaise: 24000,
	}
	got := coarseRide(ride)

	if !got.Approximate || got.Customer != nil || got.Car.Registration != "" ||
		got.Car.Transmission != "manual" || got.FarePaise != 24000 {
		t.Errorf("coarse ride = %+v", got)
	}
	if got.Pickup != (domain.RidePlace{Address: "Saket, New Delhi", Lat: 28.52, Lng: 77.21}) {
		t.Errorf("pickup = %+v", got.Pickup)
	}
	if got.Destination.Address != "IGI Airport, New Delhi" || got.Destination.Lat != 28.56 {
		t.Errorf("destination = %+v", got.Destination)
	}
	if s := got.Stops[0]; s.Task != "" || s.Place.Address != "Vasant Kunj, New Delhi" || s.DepartBy == nil {
		t.Errorf("stop = %+v", s)
	}
	// The original is untouched: the accepted view still has everything.
	if ride.Car.Registration != "DL3CAB1234" || ride.Stops[0].Task == "" || ride.Customer == nil {
		t.Error("coarseRide changed the ride it was given")
	}
}
