package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// DriverRideHandler serves the driver app's ride panels: the open requests
// feed, the driver's own rides, the step-by-step ride actions, earnings and
// the online/offline switch. Every route runs behind requireAuth against the
// driver session store, so the driver id always comes from the session.
type DriverRideHandler struct {
	svc *service.DriverRideService
}

// NewDriverRideHandler wires the handler to its service.
func NewDriverRideHandler(svc *service.DriverRideService) *DriverRideHandler {
	return &DriverRideHandler{svc: svc}
}

type ridesResponse struct {
	Rides []domain.DriverRide `json:"rides"`
}

type rideResponse struct {
	Ride domain.DriverRide `json:"ride"`
}

// startRequest is the body of POST /driver/rides/{id}/start: the code the
// customer reads out from their app.
type startRequest struct {
	OTP string `json:"otp"`
}

// dutyRequest is the PUT /driver/duty body. Lat/Lng are optional: a driver
// can go online before the first GPS fix arrives.
type dutyRequest struct {
	Online bool     `json:"online"`
	Lat    *float64 `json:"lat"`
	Lng    *float64 `json:"lng"`
}

// Requests handles GET /driver/rides/requests[?lat=..&lng=..].
func (h *DriverRideHandler) Requests(w http.ResponseWriter, r *http.Request) {
	at, ok := queryLatLng(r)
	if !ok {
		writeError(w, http.StatusBadRequest, "lat and lng must be numbers")
		return
	}
	rides, err := h.svc.Requests(r.Context(), userIDFrom(r.Context()), at)
	if err != nil {
		writeRideError(w, err, "could not load ride requests")
		return
	}
	writeJSON(w, http.StatusOK, ridesResponse{Rides: rides})
}

// Mine handles GET /driver/rides.
func (h *DriverRideHandler) Mine(w http.ResponseWriter, r *http.Request) {
	rides, err := h.svc.MyRides(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		writeRideError(w, err, "could not load your rides")
		return
	}
	writeJSON(w, http.StatusOK, ridesResponse{Rides: rides})
}

// Act handles POST /driver/rides/{id}/{action}, where action is accept,
// decline, arrive, start, complete or release. Start takes a {"otp": "1234"}
// body. Accept and the three steps answer with the updated ride; decline and
// release with 204.
func (h *DriverRideHandler) Act(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	driverID, rideID := userIDFrom(ctx), r.PathValue("id")

	var (
		ride domain.DriverRide
		err  error
	)
	switch r.PathValue("action") {
	case "accept":
		ride, err = h.svc.Accept(ctx, driverID, rideID)
	case "arrive":
		ride, err = h.svc.Arrive(ctx, driverID, rideID)
	case "start":
		var req startRequest
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, "send the start code as {\"otp\": \"1234\"}")
			return
		}
		ride, err = h.svc.Start(ctx, driverID, rideID, strings.TrimSpace(req.OTP))
	case "complete":
		ride, err = h.svc.Complete(ctx, driverID, rideID)
	case "decline":
		err = h.svc.Decline(ctx, driverID, rideID)
	case "release":
		err = h.svc.Release(ctx, driverID, rideID)
	default:
		writeError(w, http.StatusNotFound, "unknown ride action")
		return
	}
	if err != nil {
		writeRideError(w, err, "could not update the ride")
		return
	}
	if ride.ID == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	writeJSON(w, http.StatusOK, rideResponse{Ride: ride})
}

// Earnings handles GET /driver/earnings.
func (h *DriverRideHandler) Earnings(w http.ResponseWriter, r *http.Request) {
	e, err := h.svc.Earnings(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		writeRideError(w, err, "could not load earnings")
		return
	}
	writeJSON(w, http.StatusOK, e)
}

// SetDuty handles PUT /driver/duty.
func (h *DriverRideHandler) SetDuty(w http.ResponseWriter, r *http.Request) {
	var req dutyRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	var at *service.LatLng
	if req.Lat != nil && req.Lng != nil {
		at = &service.LatLng{Lat: *req.Lat, Lng: *req.Lng}
	}
	if err := h.svc.SetDuty(r.Context(), userIDFrom(r.Context()), req.Online, at); err != nil {
		writeRideError(w, err, "could not update your status")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"online": req.Online})
}

// queryLatLng reads optional ?lat=&lng=. ok is false only when they are
// present but not numbers.
func queryLatLng(r *http.Request) (*service.LatLng, bool) {
	q := r.URL.Query()
	if q.Get("lat") == "" || q.Get("lng") == "" {
		return nil, true
	}
	lat, err1 := strconv.ParseFloat(q.Get("lat"), 64)
	lng, err2 := strconv.ParseFloat(q.Get("lng"), 64)
	if err1 != nil || err2 != nil {
		return nil, false
	}
	return &service.LatLng{Lat: lat, Lng: lng}, true
}

// writeRideError maps ride errors to statuses. The codes are what the app
// branches on: a taken ride is dropped from the feed, a KYC block shows the
// documents screen.
func writeRideError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, service.ErrDriverNotCleared):
		writeErrorCode(w, http.StatusForbidden, "kyc_not_cleared", err.Error(), 0)
	case errors.Is(err, repository.ErrRideNotFound):
		writeErrorCode(w, http.StatusNotFound, "ride_not_found", err.Error(), 0)
	case errors.Is(err, repository.ErrRideUnavailable):
		writeErrorCode(w, http.StatusConflict, "ride_unavailable", err.Error(), 0)
	case errors.Is(err, repository.ErrRideStateConflict):
		writeErrorCode(w, http.StatusConflict, "ride_state", err.Error(), 0)
	case errors.Is(err, service.ErrTransmissionMismatch):
		writeErrorCode(w, http.StatusConflict, "transmission_mismatch", err.Error(), 0)
	case errors.Is(err, service.ErrRideClash):
		writeErrorCode(w, http.StatusConflict, "ride_clash", err.Error(), 0)
	case errors.Is(err, service.ErrRideInProgress):
		writeErrorCode(w, http.StatusConflict, "ride_in_progress", err.Error(), 0)
	case errors.Is(err, service.ErrStartOTPIncorrect):
		writeErrorCode(w, http.StatusUnprocessableEntity, "start_otp_incorrect", err.Error(), 0)
	case errors.Is(err, service.ErrStartOTPReset):
		writeErrorCode(w, http.StatusUnprocessableEntity, "start_otp_reset", err.Error(), 0)
	case errors.Is(err, repository.ErrDriverNotFound):
		writeError(w, http.StatusNotFound, "driver not found")
	default:
		slog.Error("rides: request failed", "error", err)
		writeError(w, http.StatusInternalServerError, fallback)
	}
}
