package api

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/service"
)

// The day's SMS budget running out answers like the rate limiter did: a
// 429 rate_limited with Retry-After.
func TestWriteServiceError_SMSBudget(t *testing.T) {
	rec := httptest.NewRecorder()
	writeServiceError(rec, &service.SMSBudgetError{RetryAfter: 2 * time.Hour})
	if rec.Code != http.StatusTooManyRequests || !strings.Contains(rec.Body.String(), `"code":"rate_limited"`) ||
		rec.Header().Get("Retry-After") != "7200" {
		t.Errorf("got %d %s (Retry-After %q), want 429 rate_limited after 7200s",
			rec.Code, rec.Body, rec.Header().Get("Retry-After"))
	}
}

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func TestLimitBodiesCapsJSONButNotUploads(t *testing.T) {
	// Like every real handler: a body that won't decode is a 400. The cap
	// must still come back as 413, so it can't be left to the handler.
	decode := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var v map[string]any
		if err := decodeJSON(r, &v); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	h := limitBodies(decode, isUpload)
	big := `{"pad":"` + strings.Repeat("x", maxJSONBody) + `"}`

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/me/bookings", strings.NewReader(big)))
	if rec.Code != http.StatusRequestEntityTooLarge || !strings.Contains(rec.Body.String(), "body_too_large") {
		t.Fatalf("oversized JSON body: got %d %s, want 413 body_too_large", rec.Code, rec.Body)
	}

	// Chunked: no Content-Length to refuse up front.
	chunked := httptest.NewRequest(http.MethodPost, "/me/bookings", io.MultiReader(strings.NewReader(big)))
	chunked.ContentLength = -1
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, chunked)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized chunked JSON body: got %d, want 413", rec.Code)
	}

	// A chunked body under the cap reaches the handler whole.
	small := httptest.NewRequest(http.MethodPost, "/me/bookings", io.MultiReader(strings.NewReader(`{"ok":true}`)))
	small.ContentLength = -1
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, small)
	if rec.Code != http.StatusOK {
		t.Fatalf("small chunked JSON body: got %d %s, want 200", rec.Code, rec.Body)
	}

	read := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := io.ReadAll(r.Body); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	rec = httptest.NewRecorder()
	limitBodies(read, isUpload).ServeHTTP(rec,
		httptest.NewRequest(http.MethodPost, "/driver/kyc/documents/selfie", strings.NewReader(big)))
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

// Each caller gets its own allowance — per address for IPv4, per /64 for
// IPv6 — and there is no shared budget here: the day's SMS spend is counted
// where a text is sent, so junk requests from many hosts can't lock
// everyone out.
func TestRateLimitPerIP(t *testing.T) {
	rule := rateLimitRule{
		match: func(r *http.Request) bool { return r.URL.Path == "/auth/otp" },
		perIP: newWindowLimiter(2, time.Hour),
	}
	h := rateLimit(okHandler(), []rateLimitRule{rule})
	hit := func(ip, path string) int {
		r := httptest.NewRequest(http.MethodPost, path, nil)
		r.RemoteAddr = net.JoinHostPort(ip, "1234")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, r)
		return rec.Code
	}

	for i := 1; i <= 2; i++ {
		if code := hit("1.1.1.1", "/auth/otp"); code != 200 {
			t.Fatalf("hit %d from one IP: got %d, want 200", i, code)
		}
	}
	if code := hit("1.1.1.1", "/auth/otp"); code != http.StatusTooManyRequests {
		t.Fatalf("third hit from one IP: got %d, want 429", code)
	}
	for i, ip := range []string{"2.2.2.2", "3.3.3.3", "4.4.4.4", "5.5.5.5"} {
		if code := hit(ip, "/auth/otp"); code != 200 {
			t.Fatalf("caller %d (%s): got %d, want 200 — no shared budget", i+1, ip, code)
		}
	}
	// One IPv6 /64 is one caller, whatever addresses it rotates through.
	hit("2001:db8:1:2::1", "/auth/otp")
	hit("2001:db8:1:2:aaaa::9", "/auth/otp")
	if code := hit("2001:db8:1:2:ffff:ffff:ffff:ffff", "/auth/otp"); code != http.StatusTooManyRequests {
		t.Fatalf("third hit from one /64: got %d, want 429", code)
	}
	if code := hit("2001:db8:1:3::1", "/auth/otp"); code != 200 {
		t.Fatalf("the next /64: got %d, want 200", code)
	}
	if hit("1.1.1.1", "/healthz") != 200 {
		t.Fatal("unmatched routes are never limited")
	}
}

func TestLimitKey(t *testing.T) {
	for in, want := range map[string]string{
		"203.0.113.9":            "203.0.113.9",
		"::ffff:203.0.113.9":     "203.0.113.9",
		"2001:db8:1:2:3:4:5:6":   "2001:db8:1:2::/64",
		"fe80::1%eth0":           "fe80::/64",
		"not-an-ip":              "not-an-ip",
		"2001:db8:abcd:12::dead": "2001:db8:abcd:12::/64",
	} {
		if got := limitKey(in); got != want {
			t.Errorf("limitKey(%q) = %q, want %q", in, got, want)
		}
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
	for i := 1; i <= 2; i++ {
		if code := call(); code != http.StatusUnauthorized {
			t.Fatalf("wrong token %d: got %d, want a plain 401", i, code)
		}
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

func TestReadyzReflectsTheDatabase(t *testing.T) {
	for _, tc := range []struct {
		ready error
		want  int
	}{
		{nil, http.StatusOK},
		{errors.New("db down"), http.StatusServiceUnavailable},
	} {
		h := NewRouter(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "", nil,
			func(context.Context) error { return tc.ready }, nil, AppPolicy{})
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
		if rec.Code != tc.want {
			t.Errorf("ready=%v: got %d, want %d", tc.ready, rec.Code, tc.want)
		}
	}
}

func TestSecurityHeadersAndDeadline(t *testing.T) {
	var hasDeadline bool
	h := securityHeaders(withDeadline(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, hasDeadline = r.Context().Deadline()
	})))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/x", nil))
	if !hasDeadline {
		t.Error("requests should carry a deadline")
	}
	for _, k := range []string{"Strict-Transport-Security", "X-Content-Type-Options", "X-Frame-Options"} {
		if rec.Header().Get(k) == "" {
			t.Errorf("missing %s", k)
		}
	}
}
