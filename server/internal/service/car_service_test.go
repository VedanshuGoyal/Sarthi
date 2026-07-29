package service

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/sarthi/server/internal/domain"
)

// fakeCarStore records calls and returns canned data.
type fakeCarStore struct {
	list      []domain.Car
	upserted  domain.Car
	upsertHit bool
}

func (f *fakeCarStore) ListByUser(_ context.Context, _ string) ([]domain.Car, error) {
	return f.list, nil
}

func (f *fakeCarStore) Upsert(_ context.Context, _ string, c domain.Car) (domain.Car, error) {
	f.upsertHit = true
	f.upserted = c
	return c, nil
}

func (f *fakeCarStore) Delete(_ context.Context, _ string, carID string) (bool, error) {
	for i, c := range f.list {
		if c.ID == carID {
			f.list = append(f.list[:i:i], f.list[i+1:]...)
			return true, nil
		}
	}
	return false, nil
}

func TestCarService_List(t *testing.T) {
	store := &fakeCarStore{list: []domain.Car{{Registration: "KA01AB1234"}}}
	svc := NewCarService(store)

	got, err := svc.List(context.Background(), "u1")
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != 1 || got[0].Registration != "KA01AB1234" {
		t.Fatalf("unexpected list: %+v", got)
	}
}

func TestCarService_Add_normalizesRegistration(t *testing.T) {
	store := &fakeCarStore{}
	svc := NewCarService(store)

	saved, _, err := svc.Add(context.Background(), "u1", domain.Car{
		Registration: " ka 01-ab 1234 ",
		CarType:      domain.CarTypeSedan,
		Transmission: domain.TransmissionManual,
	})
	if err != nil {
		t.Fatalf("Add: %v", err)
	}
	if !store.upsertHit {
		t.Fatal("expected Upsert to be called")
	}
	if saved.Registration != "KA01AB1234" {
		t.Errorf("registration = %q, want KA01AB1234", saved.Registration)
	}
}

func TestCarService_Add_rejectsInvalid(t *testing.T) {
	svc := NewCarService(&fakeCarStore{})

	cases := map[string]domain.Car{
		"blank registration": {Registration: "   ", CarType: domain.CarTypeSedan, Transmission: domain.TransmissionManual},
		"too short":          {Registration: "AB1", CarType: domain.CarTypeSedan, Transmission: domain.TransmissionManual},
		"unknown car type":   {Registration: "KA01AB1234", CarType: "rocket", Transmission: domain.TransmissionManual},
		"unknown gearbox":    {Registration: "KA01AB1234", CarType: domain.CarTypeSedan, Transmission: "cvt-ish"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, _, err := svc.Add(context.Background(), "u1", c)
			if !errors.Is(err, ErrInvalidCar) {
				t.Fatalf("err = %v, want ErrInvalidCar", err)
			}
		})
	}
}

func TestCarService_Add_capsAtMaxCars(t *testing.T) {
	full := make([]domain.Car, MaxCars)
	for i := range full {
		full[i] = domain.Car{Registration: fmt.Sprintf("KA01AB%04d", i)}
	}
	svc := NewCarService(&fakeCarStore{list: full})

	_, _, err := svc.Add(context.Background(), "u1", domain.Car{
		Registration: "MH12CD5678",
		CarType:      domain.CarTypeSUV,
		Transmission: domain.TransmissionAutomatic,
	})
	if !errors.Is(err, ErrTooManyCars) {
		t.Fatalf("err = %v, want ErrTooManyCars", err)
	}

	// Re-adding an existing registration is an update, not a new car, so the
	// cap must not block it.
	_, _, err = svc.Add(context.Background(), "u1", domain.Car{
		Registration: full[0].Registration,
		CarType:      domain.CarTypeSUV,
		Transmission: domain.TransmissionAutomatic,
	})
	if err != nil {
		t.Fatalf("re-add at cap: %v", err)
	}
}

func TestCarService_Remove(t *testing.T) {
	store := &fakeCarStore{list: []domain.Car{
		{ID: "id-1", Registration: "KA01AB1234"},
		{ID: "id-2", Registration: "MH12CD5678"},
	}}
	svc := NewCarService(store)

	got, err := svc.Remove(context.Background(), "u1", "id-1")
	if err != nil {
		t.Fatalf("Remove: %v", err)
	}
	if len(got) != 1 || got[0].ID != "id-2" {
		t.Fatalf("unexpected list after remove: %+v", got)
	}
}

func TestCarService_Remove_notFound(t *testing.T) {
	svc := NewCarService(&fakeCarStore{list: []domain.Car{{ID: "id-1"}}})

	for name, id := range map[string]string{"unknown id": "nope", "blank id": "  "} {
		t.Run(name, func(t *testing.T) {
			_, err := svc.Remove(context.Background(), "u1", id)
			if !errors.Is(err, ErrCarNotFound) {
				t.Fatalf("err = %v, want ErrCarNotFound", err)
			}
		})
	}
}
