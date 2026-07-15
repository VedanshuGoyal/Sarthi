package service

import (
	"context"
	"errors"
	"testing"

	"github.com/sarthi/server/internal/domain"
)

// fakeRecentStore records calls and returns canned data.
type fakeRecentStore struct {
	list      []domain.RecentPickup
	upserted  domain.RecentPickup
	upsertHit bool
	limit     int
}

func (f *fakeRecentStore) ListByUser(_ context.Context, _ string, limit int) ([]domain.RecentPickup, error) {
	f.limit = limit
	return f.list, nil
}

func (f *fakeRecentStore) Upsert(_ context.Context, _ string, p domain.RecentPickup, limit int) ([]domain.RecentPickup, error) {
	f.upsertHit = true
	f.upserted = p
	f.limit = limit
	return []domain.RecentPickup{p}, nil
}

func TestRecentPickupService_List(t *testing.T) {
	store := &fakeRecentStore{list: []domain.RecentPickup{{Address: "MG Road"}}}
	svc := NewRecentPickupService(store)

	got, err := svc.List(context.Background(), "u1")
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != 1 || got[0].Address != "MG Road" {
		t.Fatalf("unexpected list: %+v", got)
	}
	if store.limit != MaxRecentPickups {
		t.Errorf("limit = %d, want %d", store.limit, MaxRecentPickups)
	}
}

func TestRecentPickupService_Remember(t *testing.T) {
	store := &fakeRecentStore{}
	svc := NewRecentPickupService(store)

	got, err := svc.Remember(context.Background(), "u1", domain.RecentPickup{
		PlaceID: "  p1  ",
		Address: "  MG Road  ",
		Lat:     12.97,
		Lng:     77.6,
	})
	if err != nil {
		t.Fatalf("Remember: %v", err)
	}
	if !store.upsertHit {
		t.Fatal("expected Upsert to be called")
	}
	// Input is trimmed before it reaches the store.
	if store.upserted.Address != "MG Road" || store.upserted.PlaceID != "p1" {
		t.Errorf("not trimmed: %+v", store.upserted)
	}
	if store.limit != MaxRecentPickups {
		t.Errorf("limit = %d, want %d", store.limit, MaxRecentPickups)
	}
	if len(got) != 1 {
		t.Errorf("unexpected result: %+v", got)
	}
}

func TestRecentPickupService_Remember_rejectsInvalid(t *testing.T) {
	svc := NewRecentPickupService(&fakeRecentStore{})

	cases := map[string]domain.RecentPickup{
		"blank address":    {Address: "   ", Lat: 12.9, Lng: 77.6},
		"null island":      {Address: "Somewhere", Lat: 0, Lng: 0},
		"lat out of range": {Address: "Somewhere", Lat: 200, Lng: 77.6},
	}
	for name, p := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := svc.Remember(context.Background(), "u1", p)
			if !errors.Is(err, ErrInvalidPickup) {
				t.Fatalf("err = %v, want ErrInvalidPickup", err)
			}
		})
	}
}
