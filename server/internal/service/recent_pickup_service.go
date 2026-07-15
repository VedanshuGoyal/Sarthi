package service

import (
	"context"
	"errors"
	"strings"

	"github.com/sarthi/server/internal/domain"
)

// MaxRecentPickups caps how many pickups are kept per user. The repository
// prunes to this on write, and the apps mirror the same number locally.
const MaxRecentPickups = 7

// ErrInvalidPickup is returned when a remembered pickup is missing an address or
// carries out-of-range coordinates.
var ErrInvalidPickup = errors.New("pickup address and coordinates are required")

// RecentPickupStore is the slice of persistence this service needs. Defined
// consumer-side so the service stays testable with a fake.
type RecentPickupStore interface {
	ListByUser(ctx context.Context, userID string, limit int) ([]domain.RecentPickup, error)
	Upsert(ctx context.Context, userID string, p domain.RecentPickup, limit int) ([]domain.RecentPickup, error)
}

// RecentPickupService reads and records a customer's pickup history.
type RecentPickupService struct {
	store RecentPickupStore
}

// NewRecentPickupService wires the service to its store.
func NewRecentPickupService(store RecentPickupStore) *RecentPickupService {
	return &RecentPickupService{store: store}
}

// List returns the user's recent pickups, newest first.
func (s *RecentPickupService) List(ctx context.Context, userID string) ([]domain.RecentPickup, error) {
	return s.store.ListByUser(ctx, userID, MaxRecentPickups)
}

// Remember records p as the user's newest pickup and returns the updated list.
// It validates and normalises the input; the store handles de-duplication and
// capping.
func (s *RecentPickupService) Remember(ctx context.Context, userID string, p domain.RecentPickup) ([]domain.RecentPickup, error) {
	p.PlaceID = strings.TrimSpace(p.PlaceID)
	p.Address = strings.TrimSpace(p.Address)
	if p.Address == "" || !validCoord(p.Lat, p.Lng) {
		return nil, ErrInvalidPickup
	}
	return s.store.Upsert(ctx, userID, p, MaxRecentPickups)
}

// validCoord rejects out-of-range and the null-island (0,0) point, which a real
// pickup never is and which usually signals a missing coordinate.
func validCoord(lat, lng float64) bool {
	if lat == 0 && lng == 0 {
		return false
	}
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}
