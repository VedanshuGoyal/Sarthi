package service

import (
	"context"
	"errors"
	"strings"

	"github.com/sarthi/server/internal/domain"
)

// MaxCars caps how many cars a customer can save — enough for any household,
// small enough to keep the booking dropdown scannable.
const MaxCars = 12

// ErrInvalidCar is returned when a saved car has a malformed registration
// number or an unknown car type or transmission.
var ErrInvalidCar = errors.New("car registration, type and transmission are required")

// ErrTooManyCars is returned when adding a new car would exceed MaxCars.
var ErrTooManyCars = errors.New("car limit reached; remove a car before adding another")

// ErrCarNotFound is returned when removing a car the user doesn't have.
var ErrCarNotFound = errors.New("car not found")

// CarStore is the slice of persistence this service needs. Defined
// consumer-side so the service stays testable with a fake.
type CarStore interface {
	ListByUser(ctx context.Context, userID string) ([]domain.Car, error)
	Upsert(ctx context.Context, userID string, c domain.Car) (domain.Car, error)
	Delete(ctx context.Context, userID, carID string) (deleted bool, err error)
}

// CarService reads and records a customer's saved cars.
type CarService struct {
	store CarStore
}

// NewCarService wires the service to its store.
func NewCarService(store CarStore) *CarService {
	return &CarService{store: store}
}

// List returns the user's saved cars, newest first.
func (s *CarService) List(ctx context.Context, userID string) ([]domain.Car, error) {
	return s.store.ListByUser(ctx, userID)
}

// Add validates and saves c for the user, returning the stored car and the
// updated list. The registration is normalised first (uppercase, separators
// stripped), so "ka 01 ab 1234" and "KA01AB1234" are the same car; re-adding
// an existing registration updates its type/transmission in place.
func (s *CarService) Add(ctx context.Context, userID string, c domain.Car) (domain.Car, []domain.Car, error) {
	c.Registration = normalizeRegistration(c.Registration)
	if !validRegistration(c.Registration) || !validCarType(c.CarType) || !validTransmission(c.Transmission) {
		return domain.Car{}, nil, ErrInvalidCar
	}

	// Enforce the cap before writing. Checked outside a transaction: a racing
	// pair of adds could land one car over the cap, which is harmless — the cap
	// is a tidiness bound, not an invariant anything else relies on.
	existing, err := s.store.ListByUser(ctx, userID)
	if err != nil {
		return domain.Car{}, nil, err
	}
	if len(existing) >= MaxCars && !hasRegistration(existing, c.Registration) {
		return domain.Car{}, nil, ErrTooManyCars
	}

	saved, err := s.store.Upsert(ctx, userID, c)
	if err != nil {
		return domain.Car{}, nil, err
	}
	cars, err := s.store.ListByUser(ctx, userID)
	if err != nil {
		return domain.Car{}, nil, err
	}
	return saved, cars, nil
}

// Remove deletes the user's car with the given id and returns the updated
// list. ErrCarNotFound when the id names no car of theirs.
func (s *CarService) Remove(ctx context.Context, userID, carID string) ([]domain.Car, error) {
	carID = strings.TrimSpace(carID)
	if carID == "" {
		return nil, ErrCarNotFound
	}
	deleted, err := s.store.Delete(ctx, userID, carID)
	if err != nil {
		return nil, err
	}
	if !deleted {
		return nil, ErrCarNotFound
	}
	return s.store.ListByUser(ctx, userID)
}

// normalizeRegistration uppercases the plate and strips everything but letters
// and digits, so display formatting ("KA 01 AB 1234") never causes duplicates.
func normalizeRegistration(reg string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(reg) {
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// validRegistration bounds a normalised plate's length. Indian plates run
// 8–10 characters, but formats vary (BH series, older state schemes), so the
// check stays permissive and only rejects the clearly malformed.
func validRegistration(reg string) bool {
	return len(reg) >= 4 && len(reg) <= 16
}

func validCarType(t domain.CarType) bool {
	switch t {
	case domain.CarTypeHatchback, domain.CarTypeSedan, domain.CarTypeSUV, domain.CarTypeLuxury:
		return true
	}
	return false
}

func validTransmission(t domain.CarTransmission) bool {
	switch t {
	case domain.TransmissionAutomatic, domain.TransmissionManual:
		return true
	}
	return false
}

// hasRegistration reports whether cars already contains the normalised plate.
func hasRegistration(cars []domain.Car, reg string) bool {
	for _, c := range cars {
		if c.Registration == reg {
			return true
		}
	}
	return false
}
