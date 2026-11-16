package api

import (
	"context"
	"errors"
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// AccountEraser erases an account on request ([service.ErasureService]).
type AccountEraser interface {
	Erase(ctx context.Context, kind domain.AccountKind, id string) (domain.ErasureReport, error)
}

// PrivacyHandler serves account deletion: each app's own account, and any
// account from the back office.
type PrivacyHandler struct {
	erasure AccountEraser
}

// NewPrivacyHandler builds the handler over the erasure service.
func NewPrivacyHandler(erasure AccountEraser) *PrivacyHandler {
	return &PrivacyHandler{erasure: erasure}
}

// DeleteCustomer handles DELETE /me/account: erase the signed-in customer.
func (h *PrivacyHandler) DeleteCustomer(w http.ResponseWriter, r *http.Request) {
	h.erase(w, r, domain.AccountCustomer, userIDFrom(r.Context()))
}

// DeleteDriver handles DELETE /driver/account: erase the signed-in driver.
func (h *PrivacyHandler) DeleteDriver(w http.ResponseWriter, r *http.Request) {
	h.erase(w, r, domain.AccountDriver, userIDFrom(r.Context()))
}

// AdminErase handles POST /admin/accounts/{kind}/{id}/erase, for requests
// that come in by email or phone. kind is customer (or user) or driver.
func (h *PrivacyHandler) AdminErase(w http.ResponseWriter, r *http.Request) {
	kind := domain.AccountKind(r.PathValue("kind"))
	if kind == "user" {
		kind = domain.AccountCustomer
	}
	h.erase(w, r, kind, r.PathValue("id"))
}

func (h *PrivacyHandler) erase(w http.ResponseWriter, r *http.Request, kind domain.AccountKind, id string) {
	if h.erasure == nil {
		writeError(w, http.StatusServiceUnavailable, "account deletion is not available")
		return
	}
	report, err := h.erasure.Erase(r.Context(), kind, id)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, report)
	case errors.Is(err, service.ErrAccountBusy):
		writeErrorCode(w, http.StatusConflict, "account_busy", err.Error(), 0)
	case errors.Is(err, service.ErrUnknownAccountKind):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrAccountNotFound):
		writeError(w, http.StatusNotFound, "account not found")
	default:
		serverError(w, "could not delete the account", err)
	}
}
