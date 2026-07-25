package service

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
)

func TestBookingService_Record(t *testing.T) {
	// Capture the default logger's output — the log line *is* the behaviour
	// under test while bookings are record-only.
	var buf bytes.Buffer
	prev := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&buf, nil)))
	t.Cleanup(func() { slog.SetDefault(prev) })

	svc := NewBookingService()
	err := svc.Record(context.Background(), "u1", " roundTrip ", map[string]any{
		"hours": 4,
		"fare":  440,
	})
	if err != nil {
		t.Fatalf("Record: %v", err)
	}

	logged := buf.String()
	for _, want := range []string{"booking confirmed", "userId=u1", "tripType=roundTrip", "hours:4"} {
		if !strings.Contains(logged, want) {
			t.Errorf("log %q missing %q", logged, want)
		}
	}
}

func TestBookingService_Record_Invalid(t *testing.T) {
	svc := NewBookingService()
	details := map[string]any{"hours": 4}

	if err := svc.Record(context.Background(), "u1", "  ", details); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("blank tripType: err = %v, want ErrInvalidBooking", err)
	}
	if err := svc.Record(context.Background(), "u1", "roundTrip", nil); !errors.Is(err, ErrInvalidBooking) {
		t.Errorf("nil details: err = %v, want ErrInvalidBooking", err)
	}
}
