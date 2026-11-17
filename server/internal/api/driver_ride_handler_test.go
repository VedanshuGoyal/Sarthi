package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/sarthi/server/internal/service"
)

// A no-show called too early is a 409 the app can branch on, saying when
// it becomes possible.
func TestWriteRideError_noShowTooEarly(t *testing.T) {
	rec := httptest.NewRecorder()
	err := fmt.Errorf("closing: %w", &service.NoShowTooEarlyError{
		At: time.Date(2026, 11, 17, 4, 45, 0, 0, time.UTC), Wait: 90 * time.Second,
	})
	writeRideError(rec, err, "could not update the ride")

	if rec.Code != http.StatusConflict || rec.Header().Get("Retry-After") != "90" {
		t.Fatalf("status %d, Retry-After %q; want 409 and 90", rec.Code, rec.Header().Get("Retry-After"))
	}
	var body errorResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Code != "no_show_too_early" || body.RetryAfterSeconds != 90 || body.Error == "" {
		t.Errorf("body = %+v", body)
	}
}
