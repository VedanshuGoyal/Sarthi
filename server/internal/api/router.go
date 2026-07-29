package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/sarthi/server/internal/service"
)

// NewRouter wires the HTTP routes for the auth/registration API. It uses the
// standard library's method-aware ServeMux (Go 1.22+). sessions authenticates
// bearer tokens for the protected routes.
func NewRouter(
	auth *service.AuthService,
	sessions *service.SessionService,
	recents *service.RecentPickupService,
	cars *service.CarService,
	bookings *service.BookingService,
) http.Handler {
	h := NewAuthHandler(auth, sessions)
	rp := NewRecentPickupHandler(recents)
	cr := NewCarHandler(cars)
	bk := NewBookingHandler(bookings)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Public onboarding endpoints.
	mux.HandleFunc("POST /auth/otp", h.RequestOTP)
	mux.HandleFunc("POST /auth/otp/resend", h.ResendOTP)
	mux.HandleFunc("POST /auth/otp/verify", h.VerifyOTP)
	mux.HandleFunc("POST /auth/register", h.Register)

	// Authenticated endpoints — require a valid session token.
	mux.HandleFunc("GET /auth/me", requireAuth(sessions, h.Me))
	mux.HandleFunc("POST /auth/logout", requireAuth(sessions, h.Logout))

	// Per-user pickup history for the ride-booking flow.
	mux.HandleFunc("GET /me/recent-pickups", requireAuth(sessions, rp.List))
	mux.HandleFunc("POST /me/recent-pickups", requireAuth(sessions, rp.Remember))

	// The customer's saved cars, picked from a dropdown when booking and
	// managed from the profile screen.
	mux.HandleFunc("GET /me/cars", requireAuth(sessions, cr.List))
	mux.HandleFunc("POST /me/cars", requireAuth(sessions, cr.Add))
	mux.HandleFunc("DELETE /me/cars/{id}", requireAuth(sessions, cr.Delete))

	// Confirmed bookings from the app; recorded server-side (log-only for now).
	mux.HandleFunc("POST /me/bookings", requireAuth(sessions, bk.Submit))

	mux.HandleFunc("GET /users", h.ListUsers)

	return withCORS(logRequests(mux))
}

// withCORS makes the API reachable from the Flutter web app, which runs on a
// different origin (localhost:<random>) and so triggers browser CORS checks.
// It reflects the request Origin and answers the preflight OPTIONS request
// directly — the method-aware mux only registers GET/POST, so OPTIONS would
// otherwise 405. Permissive by design for local dev; restrict the allowed
// origins before deploying.
func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			w.Header().Set("Access-Control-Max-Age", "600")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// logRequests is a tiny access-log middleware.
func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"duration", time.Since(start).String(),
		)
	})
}
