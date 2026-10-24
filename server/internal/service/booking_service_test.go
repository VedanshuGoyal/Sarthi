package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

// fakeBookingStore records the last insert and returns a canned booking, or a
// preset error.
type fakeBookingStore struct {
	insertHit bool
	params    repository.InsertBookingParams
	got       domain.Booking
	err       error
}

func (f *fakeBookingStore) Insert(_ context.Context, p repository.InsertBookingParams) (domain.Booking, error) {
	if f.err != nil {
		return domain.Booking{}, f.err
	}
	f.insertHit = true
	f.params = p
	f.got = domain.Booking{
		ID:       "bk-1",
		UserID:   p.UserID,
		TripType: p.TripType,
		Details:  p.Details,
	}
	return f.got, nil
}

// roundTripDetails is a round-trip payload as the customer app sends it.
func roundTripDetails() map[string]any {
	return map[string]any{
		"pickup": map[string]any{
			"address": "India Gate, New Delhi",
			"point":   map[string]any{"latitude": 28.611, "longitude": 77.2345},
		},
		"hours":       4.0,
		"scheduledAt": "2026-10-24T13:30:00.000",
		"car": map[string]any{
			"registration": "DL01AB1234", "carType": "sedan", "transmission": "automatic",
		},
		"fare": 440.0,
	}
}

func TestBookingService_Record_persists(t *testing.T) {
	store := &fakeBookingStore{}
	svc := NewBookingService(store)

	// A leading/trailing space on the trip type is trimmed before storing.
	got, err := svc.Record(context.Background(), "u1", " roundTrip ", roundTripDetails())
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
	// The wall-clock time with no offset is IST: 13:30 IST is 08:00 UTC.
	if want := time.Date(2026, 10, 24, 8, 0, 0, 0, time.UTC); !store.params.ScheduledAt.Equal(want) {
		t.Errorf("scheduledAt = %v, want %v", store.params.ScheduledAt, want)
	}
	if store.params.FarePaise != 44000 || store.params.FareEstimated {
		t.Errorf("fare = %d (estimated %v), want quoted 44000", store.params.FarePaise, store.params.FareEstimated)
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
	// Details a driver couldn't read (no pickup coordinates) are refused.
	if _, err := svc.Record(context.Background(), "u1", "roundTrip", details); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("unreadable details: err = %v, want ErrInvalidBooking", err)
	}
	if store.insertHit {
		t.Error("Insert must not be called for an invalid booking")
	}
}

func TestBookingService_Record_propagatesStoreError(t *testing.T) {
	wantErr := errors.New("db down")
	svc := NewBookingService(&fakeBookingStore{err: wantErr})

	if _, err := svc.Record(context.Background(), "u1", "roundTrip", roundTripDetails()); !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
}
