package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func TestLimitBodiesCapsJSONButNotUploads(t *testing.T) {
	read := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := io.ReadAll(r.Body); err != nil {
			w.WriteHeader(http.StatusRequestEntityTooLarge)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	h := limitBodies(read, isUpload)
	big := strings.Repeat("x", maxJSONBody+1)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/me/bookings", strings.NewReader(big)))
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized JSON body: got %d, want 413", rec.Code)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/driver/kyc/documents/selfie", strings.NewReader(big)))
	if rec.Code != http.StatusOK {
		t.Fatalf("upload route must keep its own limit: got %d", rec.Code)
	}
}

func TestClientIPTrustsOnlyTheProxyEntry(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "127.0.0.1:5555"
	if got := clientIP(r); got != "127.0.0.1" {
		t.Fatalf("no XFF: got %q", got)
	}
	// A client-forged first entry is ignored; Caddy's appended one wins.
	r.Header.Set("X-Forwarded-For", "6.6.6.6, 203.0.113.9")
	if got := clientIP(r); got != "203.0.113.9" {
		t.Fatalf("got %q, want the last entry", got)
	}
}

func TestRateLimitPerIPAndGlobal(t *testing.T) {
	rule := rateLimitRule{
		match:  func(r *http.Request) bool { return r.URL.Path == "/auth/otp" },
		perIP:  newWindowLimiter(2, time.Hour),
		global: newWindowLimiter(3, time.Hour),
	}
	h := rateLimit(okHandler(), []rateLimitRule{rule})
	hit := func(ip, path string) int {
		r := httptest.NewRequest(http.MethodPost, path, nil)
		r.RemoteAddr = ip + ":1234"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, r)
		return rec.Code
	}

	if hit("1.1.1.1", "/auth/otp") != 200 || hit("1.1.1.1", "/auth/otp") != 200 {
		t.Fatal("the first two hits from one IP should pass")
	}
	if code := hit("1.1.1.1", "/auth/otp"); code != http.StatusTooManyRequests {
		t.Fatalf("third hit from one IP: got %d, want 429", code)
	}
	if hit("2.2.2.2", "/auth/otp") != 200 {
		t.Fatal("another IP has its own allowance")
	}
	// Three passed globally; the fourth caller hits the shared budget.
	if code := hit("3.3.3.3", "/auth/otp"); code != http.StatusTooManyRequests {
		t.Fatalf("global budget: got %d, want 429", code)
	}
	if hit("3.3.3.3", "/healthz") != 200 {
		t.Fatal("unmatched routes are never limited")
	}
}

func TestGuardAdminBacksOffAfterFailedTokens(t *testing.T) {
	failures := newWindowLimiter(2, time.Minute)
	reject := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	})
	h := guardAdmin(reject, failures)
	call := func() int {
		r := httptest.NewRequest(http.MethodGet, "/admin/stats", nil)
		r.RemoteAddr = "9.9.9.9:1"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, r)
		return rec.Code
	}
	if call() != http.StatusUnauthorized || call() != http.StatusUnauthorized {
		t.Fatal("the first wrong tokens get a plain 401")
	}
	if code := call(); code != http.StatusTooManyRequests {
		t.Fatalf("after repeated failures: got %d, want 429", code)
	}

	// The public HTML page and non-admin routes are untouched.
	r := httptest.NewRequest(http.MethodGet, "/admin", nil)
	r.RemoteAddr = "9.9.9.9:1"
	rec := httptest.NewRecorder()
	guardAdmin(okHandler(), failures).ServeHTTP(rec, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /admin page: got %d", rec.Code)
	}
}

func TestCORSAllowList(t *testing.T) {
	h := withCORS(okHandler(), []string{"https://ops.mojud.life"})
	for origin, want := range map[string]bool{
		"http://localhost:53211":  true,
		"http://127.0.0.1:8080":   true,
		"https://ops.mojud.life":  true,
		"https://evil.example":    false,
		"http://localhost.evil.x": false,
	} {
		r := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		r.Header.Set("Origin", origin)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, r)
		got := rec.Header().Get("Access-Control-Allow-Origin") == origin
		if got != want {
			t.Errorf("origin %s: allowed=%v, want %v", origin, got, want)
		}
	}
}

func TestLogRequestsTagsResponses(t *testing.T) {
	h := logRequests(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/x", nil))
	if rec.Code != http.StatusTeapot {
		t.Fatalf("status passthrough: got %d", rec.Code)
	}
	if len(rec.Header().Get("X-Request-ID")) != 16 {
		t.Fatalf("missing request id: %q", rec.Header().Get("X-Request-ID"))
	}
}
