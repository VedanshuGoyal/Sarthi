package api

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/sarthi/server/internal/domain"
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
// schemaless on purpose: it is stored verbatim as JSONB, and each trip type
// carries a different shape.
type bookingRequest struct {
	TripType string         `json:"tripType"`
	Details  map[string]any `json:"details"`
}

// bookingResponse confirms a stored booking, naming the id the app can use to
// refer to it once ride tracking exists.
type bookingResponse struct {
	ID     string `json:"id"`
	Status string `json:"status"`
}

// bookingsResponse is the customer's bookings list.
type bookingsResponse struct {
	Bookings []domain.CustomerBooking `json:"bookings"`
}

// List handles GET /me/bookings: the customer's bookings with status, driver
// and start code.
func (h *BookingHandler) List(w http.ResponseWriter, r *http.Request) {
	bookings, err := h.svc.ListMine(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		slog.Error("bookings: list failed", "error", err)
		writeError(w, http.StatusInternalServerError, "could not load your bookings")
		return
	}
	writeJSON(w, http.StatusOK, bookingsResponse{Bookings: bookings})
}

// Submit handles POST /me/bookings.
func (h *BookingHandler) Submit(w http.ResponseWriter, r *http.Request) {
	var req bookingRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	booking, err := h.svc.Record(r.Context(), userIDFrom(r.Context()), req.TripType, req.Details)
	if errors.Is(err, service.ErrInvalidBooking) || errors.Is(err, service.ErrBookingTooSoon) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record booking")
		return
	}
	writeJSON(w, http.StatusAccepted, bookingResponse{ID: booking.ID, Status: "received"})
}
