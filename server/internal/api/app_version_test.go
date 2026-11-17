package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

var testPolicy = AppPolicy{
	DownloadURL: "https://apps.mojud.life",
	UserApp:     AppBuilds{MinBuild: 9, LatestBuild: 10},
	DriverApp:   AppBuilds{MinBuild: 8, LatestBuild: 8},
}

// policyRouter is the real router with only the app contract wired: every
// service is nil, so a request that gets past the gate to a handler that
// needs one answers through requireAuth (401) rather than panicking.
func policyRouter(p AppPolicy) http.Handler {
	return NewRouter(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "", nil, nil, nil, p)
}

func send(h http.Handler, method, path, app, build string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, nil)
	if app != "" {
		r.Header.Set("X-App", app)
	}
	if build != "" {
		r.Header.Set("X-Build", build)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func TestMinBuildGate(t *testing.T) {
	gate := requireMinBuild(okHandler(), testPolicy)
	for _, tc := range []struct {
		name, path, app, build string
		want                   int
	}{
		{"user build below the minimum", "/me/bookings", AppUser, "8", http.StatusUpgradeRequired},
		{"driver build below the minimum", "/driver/rides", AppDriver, "7", http.StatusUpgradeRequired},
		{"user build at the minimum", "/me/bookings", AppUser, "9", http.StatusOK},
		{"newer than the latest", "/me/bookings", AppUser, "42", http.StatusOK},
		{"each app has its own minimum", "/driver/rides", AppDriver, "8", http.StatusOK},
		{"legacy build without headers", "/me/bookings", "", "", http.StatusOK},
		{"legacy driver build", "/driver/rides", "", "", http.StatusOK},
		{"debug build 0", "/me/bookings", AppUser, "0", http.StatusOK},
		{"unknown app", "/me/bookings", "web", "1", http.StatusOK},
		{"unreadable build", "/me/bookings", AppUser, "1.5.1", http.StatusOK},
		{"app without a build", "/me/bookings", AppUser, "", http.StatusOK},
		{"negative build", "/me/bookings", AppUser, "-3", http.StatusOK},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := send(gate, http.MethodGet, tc.path, tc.app, tc.build).Code; got != tc.want {
				t.Errorf("got %d, want %d", got, tc.want)
			}
		})
	}
}

func TestMinBuildGateExemptions(t *testing.T) {
	gate := requireMinBuild(okHandler(), testPolicy)
	for _, path := range []string{
		"/healthz", "/readyz", "/app/config",
		"/admin", "/admin/stats", "/admin/kyc/d1", "/users",
		"/payments/phonepe/webhook", "/kyc/digilocker/done",
	} {
		if got := send(gate, http.MethodGet, path, AppUser, "1").Code; got != http.StatusOK {
			t.Errorf("%s: got %d, want it exempt", path, got)
		}
	}
}

func TestMinBuildGateObservesOnlyByDefault(t *testing.T) {
	gate := requireMinBuild(okHandler(), AppPolicy{DownloadURL: "https://apps.mojud.life"})
	for _, app := range []string{AppUser, AppDriver} {
		if got := send(gate, http.MethodGet, "/me/bookings", app, "1").Code; got != http.StatusOK {
			t.Errorf("%s with no minimum set: got %d, want 200", app, got)
		}
	}
}

func TestUpdateRequiredBody(t *testing.T) {
	h := policyRouter(testPolicy)
	for _, tc := range []struct{ app, path, name string }{
		{AppUser, "/me/bookings", "This version of MOJUD is"},
		{AppDriver, "/driver/rides", "This version of MOJUD Driver is"},
	} {
		rec := send(h, http.MethodGet, tc.path, tc.app, "1")
		if rec.Code != http.StatusUpgradeRequired {
			t.Fatalf("%s: got %d, want 426", tc.app, rec.Code)
		}
		var body struct {
			Error       string `json:"error"`
			Code        string `json:"code"`
			DownloadURL string `json:"downloadUrl"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("%s: body %q: %v", tc.app, rec.Body, err)
		}
		if body.Code != "update_required" || body.DownloadURL != "https://apps.mojud.life" {
			t.Errorf("%s: got %+v", tc.app, body)
		}
		// Builds that predate the update screen show this text as it is.
		if !strings.HasPrefix(body.Error, tc.name) || !strings.Contains(body.Error, "apps.mojud.life") ||
			!strings.HasSuffix(body.Error, ".") {
			t.Errorf("%s: error %q should be a sentence naming the app and the site", tc.app, body.Error)
		}
		if rec.Header().Get("X-Request-ID") == "" {
			t.Errorf("%s: a 426 should pass through the access log", tc.app)
		}
	}

	// Legacy builds reach the handler as before (here, requireAuth's 401).
	if got := send(h, http.MethodGet, "/me/bookings", "", "").Code; got != http.StatusUnauthorized {
		t.Errorf("legacy request: got %d, want the handler's own 401", got)
	}
}

func TestAppConfigShape(t *testing.T) {
	// An old build can always read the contract, even below the minimum.
	rec := send(policyRouter(AppPolicy{
		DownloadURL: "https://apps.mojud.life",
		UserApp:     AppBuilds{MinBuild: 9, LatestBuild: 10},
		DriverApp:   AppBuilds{MinBuild: 8, LatestBuild: 0},
	}), http.MethodGet, "/app/config", AppUser, "1")
	if rec.Code != http.StatusOK {
		t.Fatalf("got %d, want 200", rec.Code)
	}
	var got map[string]map[string]map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("body %q: %v", rec.Body, err)
	}
	want := map[string]map[string]any{
		"user_app":   {"minBuild": 9.0, "latestBuild": 10.0, "downloadUrl": "https://apps.mojud.life"},
		"driver_app": {"minBuild": 8.0, "latestBuild": 8.0, "downloadUrl": "https://apps.mojud.life"},
	}
	for app, fields := range want {
		for k, v := range fields {
			if got["apps"][app][k] != v {
				t.Errorf("apps.%s.%s = %v, want %v (body %s)", app, k, got["apps"][app][k], v, rec.Body)
			}
		}
	}
}

func TestCORSAllowsTheVersionHeaders(t *testing.T) {
	r := httptest.NewRequest(http.MethodOptions, "/me/bookings", nil)
	r.Header.Set("Origin", "http://localhost:5000")
	rec := httptest.NewRecorder()
	withCORS(okHandler(), nil).ServeHTTP(rec, r)
	allowed := rec.Header().Get("Access-Control-Allow-Headers")
	for _, h := range []string{"X-App", "X-Build"} {
		if !strings.Contains(allowed, h) {
			t.Errorf("preflight allows %q, missing %s", allowed, h)
		}
	}
}

func TestLegacyCounterTalliesWithoutALinePerRequest(t *testing.T) {
	now := time.Date(2026, 11, 17, 9, 0, 0, 0, time.UTC)
	c := newLegacyCounter(time.Minute)
	c.now = func() time.Time { return now }

	c.add(false)
	c.add(true)
	c.add(true)
	if u, d := c.counts(); u != 1 || d != 2 {
		t.Fatalf("counts = %d user, %d driver; want 1, 2", u, d)
	}
	// Past the interval the tally is reported and starts again.
	now = now.Add(61 * time.Second)
	c.add(false)
	if u, d := c.counts(); u != 0 || d != 0 {
		t.Fatalf("after the report: %d user, %d driver; want a fresh window", u, d)
	}
}
