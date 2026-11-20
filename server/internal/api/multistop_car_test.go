package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/service"
)

// submitMultiStop posts a two-stop trip two days out as user u1, from the
// app build in xBuild ("" sends no X-App/X-Build, as APKs before them),
// naming a car when withCar is set.
func submitMultiStop(t *testing.T, store *submitStore, xBuild string, withCar bool) *httptest.ResponseRecorder {
	t.Helper()
	ist := time.FixedZone("IST", 5*60*60+30*60)
	day := time.Now().Add(48 * time.Hour).In(ist)
	at := func(hour int) string {
		return time.Date(day.Year(), day.Month(), day.Day(), hour, 0, 0, 0, ist).Format("2006-01-02T15:04:05")
	}
	car := ""
	if withCar {
		car = `,"car":{"id":"c1","registration":"DL01AB1234","carType":"sedan","transmission":"manual"}`
	}
	body := `{"tripType":"multiStop","details":{` +
		`"start":{"address":"Connaught Place","point":{"latitude":28.6315,"longitude":77.2167}},` +
		`"scheduledAt":"` + at(10) + `","stops":[` +
		`{"location":{"address":"Lajpat Nagar","point":{"latitude":28.5677,"longitude":77.2433}},` +
		`"task":"Collect the refill","departBy":"` + at(11) + `"},` +
		`{"location":{"address":"Bhikaji Cama Place","point":{"latitude":28.5679,"longitude":77.1859}},` +
		`"task":"Drop the forms","departBy":"` + at(12) + `"}]` + car + `}}`
	req := httptest.NewRequest(http.MethodPost, "/me/bookings", strings.NewReader(body))
	if xBuild != "" {
		req.Header.Set("X-App", AppUser)
		req.Header.Set("X-Build", xBuild)
	}
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, "u1"))
	rec := httptest.NewRecorder()
	NewBookingHandler(service.NewBookingService(store, nil, nil, nil)).Submit(rec, req)
	return rec
}

// POST /me/bookings, multi-stop: the released 1.6.0 app (+9), older APKs
// without build headers and debug builds book without a car, as before;
// from build 10 a multi-stop without one is 400 car_required, nothing
// stored.
func TestSubmitBooking_multiStopCar(t *testing.T) {
	for _, tc := range []struct {
		name     string
		xBuild   string
		withCar  bool
		wantCode int
	}{
		{"1.6.0 (+9), no car", "9", false, http.StatusAccepted},
		{"no build headers, no car", "", false, http.StatusAccepted},
		{"debug build, no car", "0", false, http.StatusAccepted},
		{"build 10, no car", "10", false, http.StatusBadRequest},
		{"build 10 with a car", "10", true, http.StatusAccepted},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &submitStore{}
			rec := submitMultiStop(t, store, tc.xBuild, tc.withCar)
			if rec.Code != tc.wantCode {
				t.Fatalf("status %d, want %d: %s", rec.Code, tc.wantCode, rec.Body)
			}
			if stored := store.inserts == 1; stored != (tc.wantCode == http.StatusAccepted) {
				t.Errorf("inserts = %d", store.inserts)
			}
			if tc.wantCode != http.StatusBadRequest {
				return
			}
			var body map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body["code"] != "car_required" ||
				body["error"] != "choose the car the driver will drive" {
				t.Errorf("body = %s, want code car_required", rec.Body)
			}
		})
	}
}
