package api

import (
	"errors"
	"io"
	"log/slog"
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/payment/phonepe"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// WebhookVerifier checks a gateway webhook's Authorization header
// (phonepe.Client).
type WebhookVerifier interface {
	VerifyWebhook(authorization string) bool
}

// PaymentHandler serves the customer's UPI checkout for a completed ride and
// the gateway's webhook.
type PaymentHandler struct {
	payments *service.PaymentService
	bookings *service.BookingService
	webhook  WebhookVerifier
}

// NewPaymentHandler wires the handler. webhook may be nil (payments off).
func NewPaymentHandler(payments *service.PaymentService, bookings *service.BookingService, webhook WebhookVerifier) *PaymentHandler {
	return &PaymentHandler{payments: payments, bookings: bookings, webhook: webhook}
}

// checkoutResponse is what the app opens the gateway's SDK with.
type checkoutResponse struct {
	Checkout domain.PaymentCheckout `json:"checkout"`
}

// Checkout handles POST /me/bookings/{id}/payment.
func (h *PaymentHandler) Checkout(w http.ResponseWriter, r *http.Request) {
	c, err := h.payments.Checkout(r.Context(), userIDFrom(r.Context()), r.PathValue("id"))
	if err != nil {
		writePaymentError(w, err, "could not open the payment page")
		return
	}
	writeJSON(w, http.StatusOK, checkoutResponse{Checkout: c})
}

// Sync handles POST /me/bookings/{id}/payment/sync: the app is back from the
// payment page; re-check with the gateway and return the ride.
func (h *PaymentHandler) Sync(w http.ResponseWriter, r *http.Request) {
	userID, id := userIDFrom(r.Context()), r.PathValue("id")
	if err := h.payments.Sync(r.Context(), userID, id); err != nil {
		writePaymentError(w, err, "could not check the payment")
		return
	}
	b, err := h.bookings.Get(r.Context(), userID, id)
	if err != nil {
		writeBookingError(w, err, "could not load the ride")
		return
	}
	writeJSON(w, http.StatusOK, oneBookingResponse{Booking: b})
}

// PhonePeWebhook handles POST /payments/phonepe/webhook. The body only says
// which order to look at; the order's state is read back from PhonePe.
func (h *PaymentHandler) PhonePeWebhook(w http.ResponseWriter, r *http.Request) {
	if h.webhook == nil || !h.payments.Enabled() {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	if !h.webhook.VerifyWebhook(r.Header.Get("Authorization")) {
		slog.Warn("payment: webhook with a bad Authorization header", "remote", r.RemoteAddr)
		writeError(w, http.StatusUnauthorized, "bad webhook credentials")
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 64<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not read the body")
		return
	}
	orderID, err := phonepe.WebhookOrder(body)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.payments.OrderUpdated(r.Context(), orderID); err != nil {
		// 5xx so PhonePe retries; the sweep catches it too.
		slog.Error("payment: webhook handling failed", "merchantOrderId", orderID, "error", err)
		writeError(w, http.StatusInternalServerError, "could not check the order")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// writePaymentError maps payment errors to statuses and the codes the app
// branches on.
func writePaymentError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, service.ErrPaymentsOff):
		writeErrorCode(w, http.StatusServiceUnavailable, "payments_not_configured", err.Error(), 0)
	case errors.Is(err, service.ErrAlreadyPaid):
		writeErrorCode(w, http.StatusConflict, "already_paid", err.Error(), 0)
	case errors.Is(err, repository.ErrBookingNotFound),
		errors.Is(err, repository.ErrBookingStateConflict):
		writeBookingError(w, err, fallback)
	default:
		slog.Error("payment: request failed", "error", err)
		writeErrorCode(w, http.StatusBadGateway, "payment_gateway",
			"we couldn't reach the payment service, please try again", 0)
	}
}
