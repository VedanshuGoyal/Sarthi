package api

import (
	"errors"
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/service"
)

// CarHandler serves a customer's saved cars. Both routes run behind
// requireAuth, so the user id comes from the validated session, never the body.
type CarHandler struct {
	svc *service.CarService
}

// NewCarHandler wires the handler to its service.
func NewCarHandler(svc *service.CarService) *CarHandler {
	return &CarHandler{svc: svc}
}

// carRequest is the POST body for saving a car.
type carRequest struct {
	Registration string `json:"registration"`
	CarType      string `json:"carType"`
	Transmission string `json:"transmission"`
}

// carsResponse is the list shape returned by GET.
type carsResponse struct {
	Cars []domain.Car `json:"cars"`
}

// addCarResponse names the saved car alongside the updated list, so the app
// can select it without re-deriving which row the normalised plate became.
type addCarResponse struct {
	Car  domain.Car   `json:"car"`
	Cars []domain.Car `json:"cars"`
}

// List handles GET /me/cars.
func (h *CarHandler) List(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.List(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load cars")
		return
	}
	writeJSON(w, http.StatusOK, carsResponse{Cars: items})
}

// Add handles POST /me/cars.
func (h *CarHandler) Add(w http.ResponseWriter, r *http.Request) {
	var req carRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	car, cars, err := h.svc.Add(r.Context(), userIDFrom(r.Context()), domain.Car{
		Registration: req.Registration,
		CarType:      domain.CarType(req.CarType),
		Transmission: domain.CarTransmission(req.Transmission),
	})
	if errors.Is(err, service.ErrInvalidCar) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if errors.Is(err, service.ErrTooManyCars) {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not save car")
		return
	}
	writeJSON(w, http.StatusOK, addCarResponse{Car: car, Cars: cars})
}

// Delete handles DELETE /me/cars/{id}.
func (h *CarHandler) Delete(w http.ResponseWriter, r *http.Request) {
	cars, err := h.svc.Remove(r.Context(), userIDFrom(r.Context()), r.PathValue("id"))
	if errors.Is(err, service.ErrCarNotFound) {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not remove car")
		return
	}
	writeJSON(w, http.StatusOK, carsResponse{Cars: cars})
}
