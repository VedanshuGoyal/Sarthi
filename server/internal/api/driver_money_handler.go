package api

import (
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/service"
)

// DriverMoneyHandler is the driver app's payout statement (money+ops). Its
// route runs behind the driver session, scoped to that driver.
type DriverMoneyHandler struct {
	payouts *service.PayoutService
}

// NewDriverMoneyHandler wires the handler.
func NewDriverMoneyHandler(payouts *service.PayoutService) *DriverMoneyHandler {
	return &DriverMoneyHandler{payouts: payouts}
}

// driverPayoutsResponse is the driver's recorded payouts, newest first.
type driverPayoutsResponse struct {
	Payouts []domain.DriverPayout `json:"payouts"`
}

// Payouts handles GET /driver/payouts.
func (h *DriverMoneyHandler) Payouts(w http.ResponseWriter, r *http.Request) {
	payouts, err := h.payouts.ForDriver(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		serverError(w, "could not load your payouts", err)
		return
	}
	w.Header().Set("Cache-Control", "private, no-store")
	writeJSON(w, http.StatusOK, driverPayoutsResponse{Payouts: payouts})
}
