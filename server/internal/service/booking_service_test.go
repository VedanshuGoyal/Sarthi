package service

import (
	"context"
	"errors"
	"testing"

	"github.com/sarthi/server/internal/domain"
)

// fakeBookingStore records the last insert and returns a canned booking, or a
// preset error.
type fakeBookingStore struct {
	insertHit bool
	got       domain.Booking
	err       error
}

func (f *fakeBookingStore) Insert(_ context.Context, userID, tripType string, details map[string]any) (domain.Booking, error) {
	if f.err != nil {
		return domain.Booking{}, f.err
	}
	f.insertHit = true
	f.got = domain.Booking{
		ID:       "bk-1",
		UserID:   userID,
		TripType: tripType,
		Details:  details,
	}
	return f.got, nil
}

func TestBookingService_Record_persists(t *testing.T) {
	store := &fakeBookingStore{}
	svc := NewBookingService(store)

	// A leading/trailing space on the trip type is trimmed before storing.
	got, err := svc.Record(context.Background(), "u1", " roundTrip ", map[string]any{
		"hours": 4,
		"fare":  440,
	})
	if err != nil {
		t.Fatalf("Record: %v", err)
	}
	if !store.insertHit {
		t.Fatal("expected Insert to be called")
	}
	if store.got.TripType != "roundTrip" {
		t.Errorf("stored tripType = %q, want roundTrip", store.got.TripType)
	}
	if got.ID != "bk-1" {
		t.Errorf("returned booking id = %q, want bk-1", got.ID)
	}
}

func TestBookingService_Record_rejectsInvalid(t *testing.T) {
	store := &fakeBookingStore{}
	svc := NewBookingService(store)
	details := map[string]any{"hours": 4}

	if _, err := svc.Record(context.Background(), "u1", "  ", details); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("blank tripType: err = %v, want ErrInvalidBooking", err)
	}
	if _, err := svc.Record(context.Background(), "u1", "roundTrip", nil); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("nil details: err = %v, want ErrInvalidBooking", err)
	}
	if store.insertHit {
		t.Error("Insert must not be called for an invalid booking")
	}
}

func TestBookingService_Record_propagatesStoreError(t *testing.T) {
	wantErr := errors.New("db down")
	svc := NewBookingService(&fakeBookingStore{err: wantErr})

	if _, err := svc.Record(context.Background(), "u1", "oneWay", map[string]any{"a": 1}); !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}
