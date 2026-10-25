package api

import (
	"errors"
	"io"
	"log/slog"
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
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

// oneBookingResponse is one booking after a change the customer made.
type oneBookingResponse struct {
	Booking domain.CustomerBooking `json:"booking"`
}

// cancelRequest is the POST /me/bookings/{id}/cancel body. The reason is
// optional; an empty or missing body cancels without one.
type cancelRequest struct {
	Reason string `json:"reason"`
}

// ratingRequest is the body of a rating, from either app.
type ratingRequest struct {
	Stars int    `json:"stars"`
	Note  string `json:"note"`
}

// driverLocationResponse is where the customer's driver is; Location is
// null until they share a position.
type driverLocationResponse struct {
	Location *domain.LiveLocation `json:"location"`
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

// Cancel handles POST /me/bookings/{id}/cancel.
func (h *BookingHandler) Cancel(w http.ResponseWriter, r *http.Request) {
	var req cancelRequest
	if err := decodeJSON(r, &req); err != nil && !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	b, err := h.svc.Cancel(r.Context(), userIDFrom(r.Context()), r.PathValue("id"), req.Reason)
	if err != nil {
		writeBookingError(w, err, "could not cancel the ride")
		return
	}
	writeJSON(w, http.StatusOK, oneBookingResponse{Booking: b})
}

// Rate handles POST /me/bookings/{id}/rating.
func (h *BookingHandler) Rate(w http.ResponseWriter, r *http.Request) {
	var req ratingRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "send the rating as {\"stars\": 5}")
		return
	}
	b, err := h.svc.RateDriver(r.Context(), userIDFrom(r.Context()), r.PathValue("id"), req.Stars, req.Note)
	if err != nil {
		writeBookingError(w, err, "could not save your rating")
		return
	}
	writeJSON(w, http.StatusOK, oneBookingResponse{Booking: b})
}

// DriverLocation handles GET /me/bookings/{id}/driver-location.
func (h *BookingHandler) DriverLocation(w http.ResponseWriter, r *http.Request) {
	loc, err := h.svc.DriverLocation(r.Context(), userIDFrom(r.Context()), r.PathValue("id"))
	if err != nil {
		writeBookingError(w, err, "could not find your driver")
		return
	}
	writeJSON(w, http.StatusOK, driverLocationResponse{Location: loc})
}

// writeBookingError maps the customer's booking errors to statuses and the
// codes the app branches on.
func writeBookingError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, repository.ErrBookingNotFound):
		writeErrorCode(w, http.StatusNotFound, "booking_not_found", err.Error(), 0)
	case errors.Is(err, repository.ErrBookingStateConflict):
		writeErrorCode(w, http.StatusConflict, "booking_state", err.Error(), 0)
	case errors.Is(err, service.ErrInvalidRating):
		writeErrorCode(w, http.StatusBadRequest, "invalid_rating", err.Error(), 0)
	case errors.Is(err, service.ErrNotTracking):
		writeErrorCode(w, http.StatusConflict, "not_tracking", err.Error(), 0)
	default:
		slog.Error("bookings: request failed", "error", err)
		writeError(w, http.StatusInternalServerError, fallback)
	}
}
