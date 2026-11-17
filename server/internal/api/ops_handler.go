package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// Back-office booking tools and the payments to-do list (money+ops). Every
// route here runs behind requireAdmin; every change is audited by
// OpsService with the operator from X-Admin-Actor.

// adminBookingResponse is one booking after an ops change.
type adminBookingResponse struct {
	Booking domain.AdminBooking `json:"booking"`
}

// AdminBookings handles GET /admin/bookings[?status=…][&from=YYYY-MM-DD][&to=YYYY-MM-DD][&date=YYYY-MM-DD]:
// bookings latest start first, filtered by status (requested, expired,
// accepted, arrived, in_progress, completed, cancelled, unpaid) and by IST
// start date (date is from=to=date). It carries phone numbers: no caching.
func (h *AdminHandler) AdminBookings(w http.ResponseWriter, r *http.Request) {
	if h.ops == nil {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	q := r.URL.Query()
	query := service.AdminBookingQuery{Status: q.Get("status"), From: q.Get("from"), To: q.Get("to")}
	if d := q.Get("date"); d != "" {
		query.From, query.To = d, d
	}
	bookings, err := h.ops.Bookings(r.Context(), query)
	if err != nil {
		writeOpsError(w, err, "could not list bookings")
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]any{"bookings": bookings})
}

// AssignBooking handles POST /admin/bookings/{id}/assign {"driverId": "…"}:
// gives an open ride to a cleared driver, even past the cutoff that closes
// it to drivers.
func (h *AdminHandler) AssignBooking(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DriverID string `json:"driverId"`
	}
	if !h.opsRequest(w, r, &req, `send {"driverId": "…"}`) {
		return
	}
	b, err := h.ops.Assign(r.Context(), operator(r), r.PathValue("id"), req.DriverID)
	if err != nil {
		writeOpsError(w, err, "could not assign the ride")
		return
	}
	writeJSON(w, http.StatusOK, adminBookingResponse{Booking: b})
}

// CancelBooking handles POST /admin/bookings/{id}/cancel {"reason": "…"}:
// cancels a ride at any step before it's completed. The reason is required
// and is shown to the customer and driver.
func (h *AdminHandler) CancelBooking(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Reason string `json:"reason"`
	}
	if !h.opsRequest(w, r, &req, `send {"reason": "…"}`) {
		return
	}
	b, err := h.ops.Cancel(r.Context(), operator(r), r.PathValue("id"), req.Reason)
	if err != nil {
		writeOpsError(w, err, "could not cancel the ride")
		return
	}
	writeJSON(w, http.StatusOK, adminBookingResponse{Booking: b})
}

// SettleBooking handles POST /admin/bookings/{id}/settle {"mode": "cash"|"waived",
// "reason": "…"}: marks a completed, unpaid ride paid without the gateway.
// HUMAN REVIEW REQUIRED: payments.
func (h *AdminHandler) SettleBooking(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Mode   string `json:"mode"`
		Reason string `json:"reason"`
	}
	if !h.opsRequest(w, r, &req, `send {"mode": "cash" or "waived", "reason": "…"}`) {
		return
	}
	b, err := h.ops.Settle(r.Context(), operator(r), r.PathValue("id"), domain.SettleMode(req.Mode), req.Reason)
	if err != nil {
		writeOpsError(w, err, "could not settle the ride")
		return
	}
	writeJSON(w, http.StatusOK, adminBookingResponse{Booking: b})
}

// PaymentAttention handles GET /admin/payments/attention: completed orders
// for rides already paid (refund one by hand) and orders pending for over a
// day.
func (h *AdminHandler) PaymentAttention(w http.ResponseWriter, r *http.Request) {
	if h.ops == nil {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	a, err := h.ops.PaymentAttention(r.Context())
	if err != nil {
		serverError(w, "could not list payments needing attention", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, a)
}

// AdminActions handles GET /admin/actions[?target=id][&limit=n]: the audit
// trail, newest first (default 50, at most 200).
func (h *AdminHandler) AdminActions(w http.ResponseWriter, r *http.Request) {
	if h.ops == nil {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	limit := 50
	if v := r.URL.Query().Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			writeError(w, http.StatusBadRequest, "limit must be a number")
			return
		}
		limit = n
	}
	actions, err := h.ops.RecentActions(r.Context(), r.URL.Query().Get("target"), limit)
	if err != nil {
		serverError(w, "could not list admin actions", err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]any{"actions": actions})
}

// opsRequest checks the ops tools are wired and decodes the body into dst,
// answering the request itself (and returning false) when it can't.
func (h *AdminHandler) opsRequest(w http.ResponseWriter, r *http.Request, dst any, usage string) bool {
	if h.ops == nil {
		writeError(w, http.StatusNotFound, "not found")
		return false
	}
	if err := decodeJSON(r, dst); err != nil {
		writeErrorCode(w, http.StatusBadRequest, "invalid_request", usage, 0)
		return false
	}
	return true
}

// writeOpsError maps the bookings tools' errors to statuses and codes.
func writeOpsError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, service.ErrInvalidOpsRequest):
		writeErrorCode(w, http.StatusBadRequest, "invalid_request", err.Error(), 0)
	case errors.Is(err, repository.ErrBookingNotFound), errors.Is(err, repository.ErrRideNotFound):
		writeErrorCode(w, http.StatusNotFound, "booking_not_found", repository.ErrBookingNotFound.Error(), 0)
	case errors.Is(err, repository.ErrDriverNotFound):
		writeErrorCode(w, http.StatusNotFound, "driver_not_found", err.Error(), 0)
	case errors.Is(err, repository.ErrRideUnavailable):
		writeErrorCode(w, http.StatusConflict, "ride_unavailable", "this ride isn't open any more", 0)
	case errors.Is(err, repository.ErrBookingStateConflict):
		writeErrorCode(w, http.StatusConflict, "booking_state", err.Error(), 0)
	case errors.Is(err, service.ErrDriverNotCleared):
		writeErrorCode(w, http.StatusConflict, "driver_not_cleared", "this driver isn't cleared to drive: "+err.Error(), 0)
	case errors.Is(err, service.ErrTransmissionMismatch):
		writeErrorCode(w, http.StatusConflict, "transmission_mismatch", "this driver doesn't drive the car's gearbox", 0)
	case errors.Is(err, service.ErrRideClash):
		writeErrorCode(w, http.StatusConflict, "ride_clash", "this driver already has a ride over those hours: "+err.Error(), 0)
	default:
		slog.Error("admin: "+fallback, "error", err)
		writeError(w, http.StatusInternalServerError, fallback)
	}
}
