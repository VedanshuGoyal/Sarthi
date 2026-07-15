package api

import (
	"errors"
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/service"
)

// RecentPickupHandler serves a customer's pickup history. Both routes run behind
// requireAuth, so the user id comes from the validated session, never the body.
type RecentPickupHandler struct {
	svc *service.RecentPickupService
}

// NewRecentPickupHandler wires the handler to its service.
func NewRecentPickupHandler(svc *service.RecentPickupService) *RecentPickupHandler {
	return &RecentPickupHandler{svc: svc}
}

// recentPickupRequest is the POST body for remembering a pickup.
type recentPickupRequest struct {
	PlaceID string  `json:"placeId"`
	Address string  `json:"address"`
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
}

// recentPickupsResponse is the shape returned by both routes.
type recentPickupsResponse struct {
	Recents []domain.RecentPickup `json:"recents"`
}

// List handles GET /me/recent-pickups.
func (h *RecentPickupHandler) List(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.List(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load recent pickups")
		return
	}
	writeJSON(w, http.StatusOK, recentPickupsResponse{Recents: items})
}

// Remember handles POST /me/recent-pickups.
func (h *RecentPickupHandler) Remember(w http.ResponseWriter, r *http.Request) {
	var req recentPickupRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	items, err := h.svc.Remember(r.Context(), userIDFrom(r.Context()), domain.RecentPickup{
		PlaceID: req.PlaceID,
		Address: req.Address,
		Lat:     req.Lat,
		Lng:     req.Lng,
	})
	if errors.Is(err, service.ErrInvalidPickup) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not save pickup")
		return
	}
	writeJSON(w, http.StatusOK, recentPickupsResponse{Recents: items})
}
