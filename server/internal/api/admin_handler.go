package api

import (
	"crypto/subtle"
	"encoding/csv"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// requireAdmin wraps a handler so it only runs for `Authorization: Bearer
// <ADMIN_TOKEN>`. With no admin token configured the route doesn't exist.
func requireAdmin(token string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if token == "" {
			writeError(w, http.StatusNotFound, "not found")
			return
		}
		got, ok := bearerToken(r)
		if !ok || subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
			writeError(w, http.StatusUnauthorized, "admin token required")
			return
		}
		next(w, r)
	}
}

// AdminHandler is MOJUD's back office: what drivers are owed and the
// payouts made to them, and drivers whose KYC needs a person.
type AdminHandler struct {
	payouts *service.PayoutService
	kyc     *service.DriverKYCService
}

// NewAdminHandler wires the handler.
func NewAdminHandler(payouts *service.PayoutService, kyc *service.DriverKYCService) *AdminHandler {
	return &AdminHandler{payouts: payouts, kyc: kyc}
}

// KYCReviews handles GET /admin/kyc[?status=submitted|rejected|verified|incomplete]:
// drivers in that status (default submitted — the review queue), with what
// each check returned and why they weren't cleared automatically.
func (h *AdminHandler) KYCReviews(w http.ResponseWriter, r *http.Request) {
	status := domain.KYCStatus(r.URL.Query().Get("status"))
	if status == "" {
		status = domain.KYCSubmitted
	}
	switch status {
	case domain.KYCSubmitted, domain.KYCRejected, domain.KYCVerified, domain.KYCIncomplete:
	default:
		writeError(w, http.StatusBadRequest, "unknown status")
		return
	}
	reviews, err := h.kyc.ListKYCReviews(r.Context(), status)
	if err != nil {
		slog.Error("admin: listing kyc reviews", "error", err)
		writeError(w, http.StatusInternalServerError, "could not list drivers")
		return
	}
	if reviews == nil {
		reviews = []domain.KYCReview{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"drivers": reviews})
}

// DecideKYC handles POST /admin/kyc/{driverId} {"status": "verified"|"rejected",
// "note": "..."}. The note is shown to the driver; a rejection needs one.
func (h *AdminHandler) DecideKYC(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Status string `json:"status"`
		Note   string `json:"note"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	err := h.kyc.DecideKYC(r.Context(), r.PathValue("driverId"), domain.KYCStatus(req.Status), req.Note)
	switch {
	case err == nil:
		w.WriteHeader(http.StatusNoContent)
	case errors.Is(err, service.ErrInvalidProfile):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrDriverNotFound):
		writeError(w, http.StatusNotFound, "driver not found")
	default:
		slog.Error("admin: deciding kyc", "error", err)
		writeError(w, http.StatusInternalServerError, "could not save the decision")
	}
}

// duePayoutsResponse is the payouts list, read at AsOf — pass it back when
// recording each transfer.
type duePayoutsResponse struct {
	AsOf    time.Time          `json:"asOf"`
	Drivers []domain.PayoutDue `json:"drivers"`
}

// DuePayouts handles GET /admin/payouts/due[?asOf=RFC3339][&format=csv].
// The CSV has one row per driver for a bank's bulk-transfer upload.
func (h *AdminHandler) DuePayouts(w http.ResponseWriter, r *http.Request) {
	var asOf time.Time
	if v := r.URL.Query().Get("asOf"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			writeError(w, http.StatusBadRequest, "asOf must be an RFC 3339 time")
			return
		}
		asOf = t
	}
	due, asOf, err := h.payouts.Due(r.Context(), asOf)
	if err != nil {
		slog.Error("admin: listing payouts failed", "error", err)
		writeError(w, http.StatusInternalServerError, "could not list payouts")
		return
	}
	if r.URL.Query().Get("format") != "csv" {
		writeJSON(w, http.StatusOK, duePayoutsResponse{AsOf: asOf, Drivers: due})
		return
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition",
		fmt.Sprintf(`attachment; filename="mojud-payouts-%s.csv"`, asOf.Format("20060102-1504")))
	cw := csv.NewWriter(w)
	_ = cw.Write([]string{"driver_id", "name", "phone", "rides", "amount_rupees",
		"account_holder", "account_number", "ifsc", "as_of"})
	for _, d := range due {
		_ = cw.Write([]string{d.DriverID, d.DriverName, d.DriverPhone, strconv.Itoa(d.Rides),
			fmt.Sprintf("%d.%02d", d.AmountPaise/100, d.AmountPaise%100),
			d.AccountHolderName, d.AccountNumber, d.IFSCCode, asOf.Format(time.RFC3339Nano)})
	}
	cw.Flush()
}

// payoutRequest records one bank transfer.
type payoutRequest struct {
	DriverID  string    `json:"driverId"`
	Reference string    `json:"reference"`
	AsOf      time.Time `json:"asOf"`
}

// RecordPayout handles POST /admin/payouts.
func (h *AdminHandler) RecordPayout(w http.ResponseWriter, r *http.Request) {
	var req payoutRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, `send {"driverId": "…", "reference": "UTR…", "asOf": "…"}`)
		return
	}
	p, err := h.payouts.Record(r.Context(), req.DriverID, req.Reference, req.AsOf)
	switch {
	case errors.Is(err, service.ErrInvalidPayout):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrNothingToPayOut), errors.Is(err, repository.ErrRideNotFound):
		writeErrorCode(w, http.StatusConflict, "nothing_to_pay_out", repository.ErrNothingToPayOut.Error(), 0)
	case err != nil:
		slog.Error("admin: recording payout failed", "error", err)
		writeError(w, http.StatusInternalServerError, "could not record the payout")
	default:
		writeJSON(w, http.StatusCreated, map[string]domain.DriverPayout{"payout": p})
	}
}
