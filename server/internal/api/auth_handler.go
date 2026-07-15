package api

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// dateLayout is the wire format for date-of-birth (calendar date, no time).
const dateLayout = "2006-01-02"

// SessionRevoker ends a session by token (backs POST /auth/logout).
type SessionRevoker interface {
	Revoke(ctx context.Context, token string) error
}

// AuthHandler exposes the auth/registration endpoints over HTTP.
type AuthHandler struct {
	auth     *service.AuthService
	sessions SessionRevoker
}

// NewAuthHandler builds the handler over the auth service and session store.
func NewAuthHandler(auth *service.AuthService, sessions SessionRevoker) *AuthHandler {
	return &AuthHandler{auth: auth, sessions: sessions}
}

// authResponse is the wire shape for a completed auth step. For a not-yet-
// registered number after OTP verify, only Registered (false) is sent; once
// logged in it also carries the token and user.
type authResponse struct {
	Registered bool         `json:"registered"`
	Token      string       `json:"token,omitempty"`
	User       *domain.User `json:"user,omitempty"`
}

func newAuthResponse(r service.AuthResult) authResponse {
	resp := authResponse{Registered: r.Registered}
	if r.Registered {
		user := r.User
		resp.Token = r.Token
		resp.User = &user
	}
	return resp
}

type otpRequest struct {
	PhoneE164 string `json:"phoneE164"`
}

// RequestOTP handles POST /auth/otp.
func (h *AuthHandler) RequestOTP(w http.ResponseWriter, r *http.Request) {
	var req otpRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}
	if err := h.auth.RequestOTP(r.Context(), req.PhoneE164); err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, nil)
}

// ResendOTP handles POST /auth/otp/resend — re-send the code to the same number.
func (h *AuthHandler) ResendOTP(w http.ResponseWriter, r *http.Request) {
	var req otpRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}
	if err := h.auth.ResendOTP(r.Context(), req.PhoneE164); err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, nil)
}

type verifyOtpRequest struct {
	PhoneE164 string `json:"phoneE164"`
	Code      string `json:"code"`
}

// VerifyOTP handles POST /auth/otp/verify. On success it either logs an
// existing account in (returns token + user) or reports the number as new
// (`registered:false`), in which case the client collects a profile and calls
// Register.
func (h *AuthHandler) VerifyOTP(w http.ResponseWriter, r *http.Request) {
	var req verifyOtpRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}
	result, err := h.auth.VerifyOTP(r.Context(), req.PhoneE164, req.Code)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newAuthResponse(result))
}

type registerRequest struct {
	PhoneE164   string `json:"phoneE164"`
	Name        string `json:"name"`
	Email       string `json:"email"`
	DateOfBirth string `json:"dateOfBirth"` // "YYYY-MM-DD"
}

// Register handles POST /auth/register.
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}

	dob, err := time.Parse(dateLayout, req.DateOfBirth)
	if err != nil {
		writeError(w, http.StatusBadRequest, "dateOfBirth must be YYYY-MM-DD")
		return
	}

	result, err := h.auth.Register(r.Context(), service.RegisterParams{
		PhoneE164:   req.PhoneE164,
		Name:        req.Name,
		Email:       req.Email,
		DateOfBirth: dob,
	})
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, newAuthResponse(result))
}

// Me handles GET /auth/me — the authenticated user's own account. The auth
// middleware has already validated the token and put the user id in context.
func (h *AuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	user, err := h.auth.CurrentUser(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

// Logout handles POST /auth/logout — revoke the caller's session token.
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	if err := h.sessions.Revoke(r.Context(), tokenFrom(r.Context())); err != nil {
		writeError(w, http.StatusInternalServerError, "could not log out")
		return
	}
	writeJSON(w, http.StatusOK, nil)
}

// ListUsers handles GET /users — every registered account, newest first.
func (h *AuthHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := h.auth.ListUsers(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list users")
		return
	}
	writeJSON(w, http.StatusOK, users)
}

// writeServiceError maps domain/service errors to HTTP status codes.
func writeServiceError(w http.ResponseWriter, err error) {
	var locked *service.OTPLockedError
	switch {
	case errors.As(err, &locked):
		writeErrorCode(w, http.StatusTooManyRequests, "otp_resend_locked",
			locked.Error(), int(locked.RetryAfter.Seconds()))
	case errors.Is(err, service.ErrOTPInvalidated):
		writeErrorCode(w, http.StatusTooManyRequests, "otp_invalidated", err.Error(), 0)
	case errors.Is(err, service.ErrInvalidOTP):
		writeErrorCode(w, http.StatusUnauthorized, "otp_incorrect", err.Error(), 0)
	case errors.Is(err, repository.ErrUserNotFound):
		writeError(w, http.StatusNotFound, "account not found")
	case errors.Is(err, repository.ErrPhoneTaken):
		writeError(w, http.StatusConflict, err.Error())
	case errors.Is(err, service.ErrInvalidPhone),
		errors.Is(err, service.ErrInvalidName),
		errors.Is(err, service.ErrInvalidEmail),
		errors.Is(err, service.ErrInvalidDOB):
		writeError(w, http.StatusBadRequest, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, "something went wrong")
	}
}
