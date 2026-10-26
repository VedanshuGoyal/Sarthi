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
	driverAuth *service.DriverAuthService,
	driverSessions *service.SessionService,
	driverKYC *service.DriverKYCService,
	driverRides *service.DriverRideService,
	maps *service.MapsService,
	notify *service.NotifyService,
	payments *service.PaymentService,
	payouts *service.PayoutService,
	webhook WebhookVerifier,
	adminToken string,
) http.Handler {
	h := NewAuthHandler(auth, sessions)
	rp := NewRecentPickupHandler(recents)
	cr := NewCarHandler(cars)
	bk := NewBookingHandler(bookings)
	dh := NewDriverAuthHandler(driverAuth, driverSessions)
	dk := NewDriverKYCHandler(driverKYC)
	dr := NewDriverRideHandler(driverRides)
	mp := NewMapsHandler(maps)
	pt := NewPushTokenHandler(notify)
	pay := NewPaymentHandler(payments, bookings, webhook)
	adm := NewAdminHandler(payouts)

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

	// Confirmed bookings from the app, and the customer's list of them with
	// status, assigned driver and start code.
	mux.HandleFunc("POST /me/bookings", requireAuth(sessions, bk.Submit))
	mux.HandleFunc("GET /me/bookings", requireAuth(sessions, bk.List))

	// Before the trip starts the customer can cancel it; once it's done they
	// rate the driver; while the driver is on the way (or driving) they can
	// see where the driver is.
	mux.HandleFunc("POST /me/bookings/{id}/cancel", requireAuth(sessions, bk.Cancel))
	mux.HandleFunc("POST /me/bookings/{id}/rating", requireAuth(sessions, bk.Rate))
	mux.HandleFunc("GET /me/bookings/{id}/driver-location", requireAuth(sessions, bk.DriverLocation))

	// Paying for a completed ride by UPI: open a PhonePe checkout, then
	// re-check it on coming back. PhonePe's webhook nudges the same check.
	mux.HandleFunc("POST /me/bookings/{id}/payment", requireAuth(sessions, pay.Checkout))
	mux.HandleFunc("POST /me/bookings/{id}/payment/sync", requireAuth(sessions, pay.Sync))
	mux.HandleFunc("POST /payments/phonepe/webhook", pay.PhonePeWebhook)

	// This install's push token, for "driver assigned" notifications.
	mux.HandleFunc("PUT /me/push-token", requireAuth(sessions, pt.SaveUser))
	mux.HandleFunc("DELETE /me/push-token", requireAuth(sessions, pt.ForgetUser))

	// Short-lived Ola Maps tokens for the app's place search; the OAuth client
	// secret stays on the server.
	mux.HandleFunc("GET /maps/token", requireAuth(sessions, mp.Token))

	// Back office, behind ADMIN_TOKEN: every account, and driver payouts.
	mux.HandleFunc("GET /users", requireAdmin(adminToken, h.ListUsers))
	mux.HandleFunc("GET /admin/payouts/due", requireAdmin(adminToken, adm.DuePayouts))
	mux.HandleFunc("POST /admin/payouts", requireAdmin(adminToken, adm.RecordPayout))

	// Driver app: the same phone/OTP registration flow as the customer app,
	// but a separate account type/session (see DriverAuthHandler).
	mux.HandleFunc("POST /driver/auth/otp", dh.RequestOTP)
	mux.HandleFunc("POST /driver/auth/otp/resend", dh.ResendOTP)
	mux.HandleFunc("POST /driver/auth/otp/verify", dh.VerifyOTP)
	mux.HandleFunc("POST /driver/auth/register", dh.Register)
	mux.HandleFunc("GET /driver/auth/me", requireAuth(driverSessions, dh.Me))
	mux.HandleFunc("POST /driver/auth/logout", requireAuth(driverSessions, dh.Logout))

	// Driver KYC: the six-step Document View. Every route is scoped to the
	// session's own driver — no route takes a driver id.
	mux.HandleFunc("GET /driver/kyc", requireAuth(driverSessions, dk.Get))
	mux.HandleFunc("PATCH /driver/kyc/profile", requireAuth(driverSessions, dk.UpdateProfile))
	mux.HandleFunc("POST /driver/kyc/bank-account", requireAuth(driverSessions, dk.SetBankAccount))
	mux.HandleFunc("POST /driver/kyc/submit", requireAuth(driverSessions, dk.Submit))
	mux.HandleFunc("POST /driver/kyc/documents/{kind}", requireAuth(driverSessions, dk.UploadDocument))
	mux.HandleFunc("GET /driver/kyc/documents/{kind}/content", requireAuth(driverSessions, dk.DocumentContent))

	// Driver ride panels: open requests near the driver, their own rides,
	// the accept → arrive → start → complete steps (and rating the customer
	// after), earnings, and the online/offline switch. Scoped to the
	// session's driver like KYC.
	mux.HandleFunc("GET /driver/rides/requests", requireAuth(driverSessions, dr.Requests))
	mux.HandleFunc("GET /driver/rides", requireAuth(driverSessions, dr.Mine))
	mux.HandleFunc("POST /driver/rides/{id}/{action}", requireAuth(driverSessions, dr.Act))
	mux.HandleFunc("GET /driver/earnings", requireAuth(driverSessions, dr.Earnings))
	mux.HandleFunc("PUT /driver/duty", requireAuth(driverSessions, dr.SetDuty))

	// The driver's position while on a ride, for the customer's live map.
	// Separate from duty: sharing it doesn't put the driver online.
	mux.HandleFunc("PUT /driver/location", requireAuth(driverSessions, dr.ShareLocation))

	// This install's push token, for "new ride request" notifications.
	mux.HandleFunc("PUT /driver/push-token", requireAuth(driverSessions, pt.SaveDriver))
	mux.HandleFunc("DELETE /driver/push-token", requireAuth(driverSessions, pt.ForgetDriver))

	return withCORS(logRequests(mux))
}

// withCORS makes the API reachable from the Flutter web app, which runs on a
// different origin (localhost:<random>) and so triggers browser CORS checks.
// It reflects the request Origin and answers the preflight OPTIONS request
// directly — the method-aware mux registers no OPTIONS routes, so OPTIONS would
// otherwise 405. Permissive by design for local dev; restrict the allowed
// origins before deploying.
func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
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
