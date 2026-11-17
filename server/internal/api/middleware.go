package api

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// maxJSONBody caps every request body except KYC uploads, which set their own
// larger limit. Booking details are the biggest legitimate body, a few KB.
const maxJSONBody = 256 << 10

// limitBodies bounds request bodies so one client cannot make the server read
// (and store, and re-serve) megabytes of JSON. skip reports routes that apply
// their own limit.
func limitBodies(next http.Handler, skip func(*http.Request) bool) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil && !skip(r) {
			r.Body = http.MaxBytesReader(w, r.Body, maxJSONBody)
		}
		next.ServeHTTP(w, r)
	})
}

// isUpload matches the KYC document upload route, which reads its multipart
// body under its own limit.
func isUpload(r *http.Request) bool {
	return r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/driver/kyc/documents/")
}

// clientIP is the caller's address. Behind Caddy the TCP peer is localhost,
// so the last X-Forwarded-For entry (the one Caddy itself appended) is used.
// Earlier entries are client-supplied and never trusted.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if ip := strings.TrimSpace(parts[len(parts)-1]); ip != "" {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// windowLimiter is a fixed-window counter per key: at most max hits per
// window. It is hot, rebuildable state - a restart only forgets recent counts.
type windowLimiter struct {
	mu     sync.Mutex
	max    int
	window time.Duration
	now    func() time.Time
	hits   map[string]*windowCount
}

type windowCount struct {
	start time.Time
	n     int
}

func newWindowLimiter(max int, window time.Duration) *windowLimiter {
	return &windowLimiter{max: max, window: window, now: time.Now, hits: make(map[string]*windowCount)}
}

// allow counts a hit for key and reports whether it is within the limit; when
// not, retryAfter is when the window resets.
func (l *windowLimiter) allow(key string) (ok bool, retryAfter time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if len(l.hits) > 50_000 {
		for k, c := range l.hits {
			if now.Sub(c.start) >= l.window {
				delete(l.hits, k)
			}
		}
	}
	c := l.hits[key]
	if c == nil || now.Sub(c.start) >= l.window {
		c = &windowCount{start: now}
		l.hits[key] = c
	}
	if c.n >= l.max {
		return false, c.start.Add(l.window).Sub(now)
	}
	c.n++
	return true, 0
}

// blocked reports whether key is over the limit without counting a hit.
func (l *windowLimiter) blocked(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	c := l.hits[key]
	if c == nil || l.now().Sub(c.start) >= l.window || c.n < l.max {
		return false, 0
	}
	return true, c.start.Add(l.window).Sub(l.now())
}

// rateLimitRule throttles one set of routes: per client IP, and optionally a
// global budget shared by every caller (the daily SMS spend).
type rateLimitRule struct {
	match  func(*http.Request) bool
	perIP  *windowLimiter
	global *windowLimiter
}

// Login routes are public and each OTP send is a paid SMS. Per-number caps
// live in the OTP guard; these bound one caller trying many numbers, and the
// whole service's SMS spend. Mobile carriers in India put many users behind
// one IP (CGNAT), so the per-IP limits are generous.
func authRateLimits() []rateLimitRule {
	sends := map[string]bool{
		"/auth/otp": true, "/auth/otp/resend": true,
		"/driver/auth/otp": true, "/driver/auth/otp/resend": true,
	}
	verifies := map[string]bool{
		"/auth/otp/verify": true, "/auth/register": true,
		"/driver/auth/otp/verify": true, "/driver/auth/register": true,
	}
	return []rateLimitRule{
		{
			match:  func(r *http.Request) bool { return r.Method == http.MethodPost && sends[r.URL.Path] },
			perIP:  newWindowLimiter(30, time.Hour),
			global: newWindowLimiter(1500, 24*time.Hour),
		},
		{
			match: func(r *http.Request) bool { return r.Method == http.MethodPost && verifies[r.URL.Path] },
			perIP: newWindowLimiter(120, time.Hour),
		},
	}
}

// rateLimit applies the first matching rule to each request.
func rateLimit(next http.Handler, rules []rateLimitRule) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for _, rule := range rules {
			if !rule.match(r) {
				continue
			}
			if ok, retry := rule.perIP.allow(clientIP(r)); !ok {
				writeRateLimited(w, retry)
				return
			}
			if rule.global != nil {
				if ok, retry := rule.global.allow("global"); !ok {
					slog.Error("rate limit: global budget exhausted", "path", r.URL.Path)
					writeRateLimited(w, retry)
					return
				}
			}
			break
		}
		next.ServeHTTP(w, r)
	})
}

func writeRateLimited(w http.ResponseWriter, retry time.Duration) {
	secs := int(retry.Seconds() + 0.5)
	if secs < 1 {
		secs = 1
	}
	writeErrorCode(w, http.StatusTooManyRequests, "rate_limited",
		"too many requests; try again later", secs)
}

// isAdminPath matches the token-guarded back office (the HTML page at /admin
// is public and unguarded; everything it calls is under /admin/ or /users).
func isAdminPath(r *http.Request) bool {
	return strings.HasPrefix(r.URL.Path, "/admin/") || r.URL.Path == "/users"
}

// guardAdmin backs off callers who keep presenting a wrong admin token, and
// writes an audit line for every back-office change (payouts, KYC decisions).
func guardAdmin(next http.Handler, failures *windowLimiter) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !isAdminPath(r) {
			next.ServeHTTP(w, r)
			return
		}
		ip := clientIP(r)
		if blocked, retry := failures.blocked(ip); blocked {
			slog.Warn("admin: caller blocked after failed tokens", "ip", ip)
			writeRateLimited(w, retry)
			return
		}
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		if rec.status == http.StatusUnauthorized || rec.status == http.StatusForbidden {
			failures.allow(ip)
			slog.Warn("admin: rejected token", "ip", ip, "path", r.URL.Path)
			return
		}
		if r.Method != http.MethodGet {
			slog.Info("admin: action", "method", r.Method, "path", r.URL.Path,
				"status", rec.status, "ip", ip)
		}
	})
}

// withCORS lets browser clients on the allowed origins call the API. The
// mobile apps and the same-origin admin page need no CORS at all; the list is
// for the Flutter web build during development (any localhost port).
func withCORS(next http.Handler, allowed []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" && originAllowed(origin, allowed) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-App, X-Build, Idempotency-Key")
			w.Header().Set("Access-Control-Max-Age", "600")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// originAllowed matches an exact origin from allowed, or any port on
// localhost/127.0.0.1 (local Flutter web runs pick a random port).
func originAllowed(origin string, allowed []string) bool {
	for _, a := range allowed {
		if origin == a {
			return true
		}
	}
	for _, local := range []string{"http://localhost", "http://127.0.0.1"} {
		if origin == local || strings.HasPrefix(origin, local+":") {
			return true
		}
	}
	return false
}

// statusRecorder captures the status code a handler writes.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// logRequests writes one access-log line per request with its status, and
// tags the response with an X-Request-ID that appears in the log, so a user's
// report can be matched to the server's view. 5xx lines log at error level.
// Requests from an app that names its build (X-App/X-Build) carry it too.
func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		id := newRequestID()
		w.Header().Set("X-Request-ID", id)
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		level := slog.LevelInfo
		if rec.status >= 500 {
			level = slog.LevelError
		}
		attrs := []any{
			"id", id,
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration", time.Since(start).String(),
		}
		if c, ok := identifyClient(r); ok {
			attrs = append(attrs, "app", c.app, "build", c.build)
		}
		slog.Log(r.Context(), level, "request", attrs...)
	})
}

func newRequestID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return hex.EncodeToString(b)
}

// requestDeadline bounds how long any one request may run, so a stuck
// upstream (SMS, KYC, maps, gateway) can't pile up goroutines and memory.
// The slowest upstream (Surepass, 45 s) fits inside it.
const requestDeadline = 60 * time.Second

func withDeadline(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), requestDeadline)
		defer cancel()
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// securityHeaders sets the headers every response should carry. The API is
// only served over HTTPS (Caddy), so HSTS is safe to send.
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Strict-Transport-Security", "max-age=31536000")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-Frame-Options", "DENY")
		next.ServeHTTP(w, r)
	})
}
