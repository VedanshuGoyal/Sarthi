package api

import (
	"errors"
	"net/http"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// DriverAuthHandler exposes the driver app's auth/registration endpoints over
// HTTP, mirroring [AuthHandler] for the customer app.
type DriverAuthHandler struct {
	auth     *service.DriverAuthService
	sessions SessionRevoker
}

// NewDriverAuthHandler builds the handler over the driver auth service and
// session store.
func NewDriverAuthHandler(auth *service.DriverAuthService, sessions SessionRevoker) *DriverAuthHandler {
	return &DriverAuthHandler{auth: auth, sessions: sessions}
}

// driverAuthResponse is the wire shape for a completed auth step. For a
// not-yet-registered number after OTP verify, only Registered (false) is
// sent; once logged in it also carries the token and driver.
type driverAuthResponse struct {
	Registered bool           `json:"registered"`
	Token      string         `json:"token,omitempty"`
	Driver     *domain.Driver `json:"driver,omitempty"`
}

func newDriverAuthResponse(r service.DriverAuthResult) driverAuthResponse {
	resp := driverAuthResponse{Registered: r.Registered}
	if r.Registered {
		driver := r.Driver
		resp.Token = r.Token
		resp.Driver = &driver
	}
	return resp
}

// RequestOTP handles POST /driver/auth/otp.
func (h *DriverAuthHandler) RequestOTP(w http.ResponseWriter, r *http.Request) {
	var req otpRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}
	if err := h.auth.RequestOTP(r.Context(), req.PhoneE164); err != nil {
		writeDriverServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, nil)
}

// ResendOTP handles POST /driver/auth/otp/resend — re-send the code to the
// same number.
func (h *DriverAuthHandler) ResendOTP(w http.ResponseWriter, r *http.Request) {
	var req otpRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}
	if err := h.auth.ResendOTP(r.Context(), req.PhoneE164); err != nil {
		writeDriverServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, nil)
}

// VerifyOTP handles POST /driver/auth/otp/verify. On success it either logs an
// existing driver in (returns token + driver) or reports the number as new
// (`registered:false`), in which case the client collects a name and calls
// Register.
func (h *DriverAuthHandler) VerifyOTP(w http.ResponseWriter, r *http.Request) {
	var req verifyOtpRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}
	result, err := h.auth.VerifyOTP(r.Context(), req.PhoneE164, req.Code)
	if err != nil {
		writeDriverServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newDriverAuthResponse(result))
}

type driverRegisterRequest struct {
	PhoneE164 string `json:"phoneE164"`
	Name      string `json:"name"`
}

// Register handles POST /driver/auth/register.
func (h *DriverAuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req driverRegisterRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return
	}

	result, err := h.auth.Register(r.Context(), service.DriverRegisterParams{
		PhoneE164: req.PhoneE164,
		Name:      req.Name,
	})
	if err != nil {
		writeDriverServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, newDriverAuthResponse(result))
}

// Me handles GET /driver/auth/me — the authenticated driver's own account. The
// auth middleware has already validated the token and put the driver id in
// context.
func (h *DriverAuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	driver, err := h.auth.CurrentDriver(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		writeDriverServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, driver)
}

// Logout handles POST /driver/auth/logout — revoke the caller's session token.
func (h *DriverAuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	if err := h.sessions.Revoke(r.Context(), tokenFrom(r.Context())); err != nil {
		writeError(w, http.StatusInternalServerError, "could not log out")
		return
	}
	writeJSON(w, http.StatusOK, nil)
}

// writeDriverServiceError maps domain/service errors to HTTP status codes,
// mirroring [writeServiceError] for the driver-specific sentinel errors.
func writeDriverServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, repository.ErrDriverNotFound):
		writeError(w, http.StatusNotFound, "account not found")
	case errors.Is(err, repository.ErrDriverPhoneTaken):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeServiceError(w, err)
	}
}
