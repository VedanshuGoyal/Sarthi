package api

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/sarthi/server/internal/service"
)

// MapsHandler serves Ola Maps bearer tokens to signed-in customers. The route
// runs behind requireAuth, so only app users can draw on the Ola account.
type MapsHandler struct {
	svc *service.MapsService
	now func() time.Time
}

// NewMapsHandler wires the handler to its service.
func NewMapsHandler(svc *service.MapsService) *MapsHandler {
	return &MapsHandler{svc: svc, now: time.Now}
}

// mapsTokenResponse is the GET /maps/token body. ExpiresIn is relative
// (seconds from now) rather than a timestamp, so a phone with a wrong clock
// still refreshes at the right moment.
type mapsTokenResponse struct {
	AccessToken string `json:"accessToken"`
	ExpiresIn   int    `json:"expiresIn"`
}

// Token handles GET /maps/token.
func (h *MapsHandler) Token(w http.ResponseWriter, r *http.Request) {
	token, err := h.svc.Token(r.Context())
	switch {
	case errors.Is(err, service.ErrMapsNotConfigured):
		writeErrorCode(w, http.StatusServiceUnavailable, "maps_not_configured",
			"map search isn't set up on the server", 0)
	case err != nil:
		slog.Error("maps: minting Ola token", "error", err)
		writeErrorCode(w, http.StatusBadGateway, "maps_unavailable",
			"could not reach the maps provider", 0)
	default:
		w.Header().Set("Cache-Control", "no-store")
		writeJSON(w, http.StatusOK, mapsTokenResponse{
			AccessToken: token.AccessToken,
			ExpiresIn:   int(token.ExpiresAt.Sub(h.now()).Seconds()),
		})
	}
}
