package api

import (
	"errors"
	"net/http"

	"github.com/sarthi/server/internal/service"
)

// BookingHandler receives confirmed bookings. The route runs behind
// requireAuth, so the user id comes from the validated session, never the body.
type BookingHandler struct {
	svc *service.BookingService
}

// NewBookingHandler wires the handler to its service.
func NewBookingHandler(svc *service.BookingService) *BookingHandler {
	return &BookingHandler{svc: svc}
}

// bookingRequest is the POST body for a confirmed booking. Details is kept
// schemaless on purpose: the service only records it for now, and each trip
// type carries a different shape.
type bookingRequest struct {
	TripType string         `json:"tripType"`
	Details  map[string]any `json:"details"`
}

// Submit handles POST /me/bookings.
func (h *BookingHandler) Submit(w http.ResponseWriter, r *http.Request) {
	var req bookingRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	err := h.svc.Record(r.Context(), userIDFrom(r.Context()), req.TripType, req.Details)
	if errors.Is(err, service.ErrInvalidBooking) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record booking")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "received"})
}
