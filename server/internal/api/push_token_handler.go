package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"github.com/sarthi/server/internal/service"
)

// PushTokenHandler registers app installs for push notifications. One
// handler serves both apps; the routes run behind requireAuth against the
// customer or the driver session store, so the account id comes from the
// session.
type PushTokenHandler struct {
	svc *service.NotifyService
}

// NewPushTokenHandler wires the handler to its service.
func NewPushTokenHandler(svc *service.NotifyService) *PushTokenHandler {
	return &PushTokenHandler{svc: svc}
}

// pushTokenRequest is the body of PUT and DELETE …/push-token.
type pushTokenRequest struct {
	Token string `json:"token"`
}

// SaveUser handles PUT /me/push-token.
func (h *PushTokenHandler) SaveUser(w http.ResponseWriter, r *http.Request) {
	h.handle(w, r, h.svc.RegisterUserDevice)
}

// ForgetUser handles DELETE /me/push-token.
func (h *PushTokenHandler) ForgetUser(w http.ResponseWriter, r *http.Request) {
	h.handle(w, r, h.svc.ForgetUserDevice)
}

// SaveDriver handles PUT /driver/push-token.
func (h *PushTokenHandler) SaveDriver(w http.ResponseWriter, r *http.Request) {
	h.handle(w, r, h.svc.RegisterDriverDevice)
}

// ForgetDriver handles DELETE /driver/push-token.
func (h *PushTokenHandler) ForgetDriver(w http.ResponseWriter, r *http.Request) {
	h.handle(w, r, h.svc.ForgetDriverDevice)
}

func (h *PushTokenHandler) handle(w http.ResponseWriter, r *http.Request, op func(ctx context.Context, ownerID, token string) error) {
	var req pushTokenRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	err := op(r.Context(), userIDFrom(r.Context()), req.Token)
	if errors.Is(err, service.ErrInvalidPushToken) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		slog.Error("push token: save/forget failed", "method", r.Method, "path", r.URL.Path, "error", err)
		writeError(w, http.StatusInternalServerError, "could not update notifications")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
