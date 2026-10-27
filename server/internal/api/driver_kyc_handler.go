package api

import (
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
	"github.com/sarthi/server/internal/storage"
)

// DriverKYCHandler serves the driver app's Document View. Every route runs
// behind requireAuth against the driver session store, so the driver id comes
// from the validated session and a driver can only ever reach their own
// documents — there is no id in any path or body.
type DriverKYCHandler struct {
	svc *service.DriverKYCService
}

// NewDriverKYCHandler wires the handler to its service.
func NewDriverKYCHandler(svc *service.DriverKYCService) *DriverKYCHandler {
	return &DriverKYCHandler{svc: svc}
}

// profileRequest is the PATCH body. Pointers throughout: the Document View
// submits one step at a time, and an absent field must not clear a stored one.
type profileRequest struct {
	Transmission         *string `json:"transmission"`
	FullName             *string `json:"fullName"`
	DateOfBirth          *string `json:"dateOfBirth"` // YYYY-MM-DD
	Gender               *string `json:"gender"`
	AadhaarNumber        *string `json:"aadhaarNumber"`
	DrivingLicenseNumber *string `json:"drivingLicenseNumber"`
}

// bankAccountRequest is the POST body for the payout step.
type bankAccountRequest struct {
	AccountHolderName string `json:"accountHolderName"`
	AccountNumber     string `json:"accountNumber"`
	IFSCCode          string `json:"ifscCode"`
}

// Get handles GET /driver/kyc.
func (h *DriverKYCHandler) Get(w http.ResponseWriter, r *http.Request) {
	kyc, err := h.svc.Load(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		h.writeKYCError(w, err, "could not load documents")
		return
	}
	writeJSON(w, http.StatusOK, kyc)
}

// UpdateProfile handles PATCH /driver/kyc/profile.
func (h *DriverKYCHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	var req profileRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	update := service.ProfileUpdate{
		Transmission:         req.Transmission,
		FullName:             req.FullName,
		Gender:               req.Gender,
		AadhaarNumber:        req.AadhaarNumber,
		DrivingLicenseNumber: req.DrivingLicenseNumber,
	}
	if req.DateOfBirth != nil {
		dob, err := time.Parse(dateLayout, *req.DateOfBirth)
		if err != nil {
			writeError(w, http.StatusBadRequest, "date of birth must be YYYY-MM-DD")
			return
		}
		update.DateOfBirth = &dob
	}

	driverID := userIDFrom(r.Context())
	if err := h.svc.UpdateProfile(r.Context(), driverID, update); err != nil {
		h.writeKYCError(w, err, "could not save these details")
		return
	}
	h.respondWithKYC(w, r, driverID)
}

// SetBankAccount handles POST /driver/kyc/bank-account.
func (h *DriverKYCHandler) SetBankAccount(w http.ResponseWriter, r *http.Request) {
	var req bankAccountRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	driverID := userIDFrom(r.Context())
	_, err := h.svc.SetBankAccount(r.Context(), driverID,
		req.AccountHolderName, req.AccountNumber, req.IFSCCode)
	if err != nil {
		h.writeKYCError(w, err, "could not save bank details")
		return
	}
	h.respondWithKYC(w, r, driverID)
}

// UploadDocument handles POST /driver/kyc/documents/{kind}.
//
// The body is the raw image, not a multipart form: the app sends exactly one
// file and no other fields, so multipart would only add a parse step and a
// temp file on both sides.
func (h *DriverKYCHandler) UploadDocument(w http.ResponseWriter, r *http.Request) {
	// MaxBytesReader stops an oversized upload at the socket instead of after
	// it has all been read into memory. One byte over the limit so reading the
	// maximum allowed image still succeeds.
	r.Body = http.MaxBytesReader(w, r.Body, service.MaxDocumentBytes+1)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			writeError(w, http.StatusRequestEntityTooLarge, service.ErrDocumentTooLarge.Error())
			return
		}
		writeError(w, http.StatusBadRequest, "could not read the uploaded image")
		return
	}

	driverID := userIDFrom(r.Context())
	kind := domain.DocumentKind(r.PathValue("kind"))
	if _, err := h.svc.UploadDocument(r.Context(), driverID, kind, raw); err != nil {
		h.writeKYCError(w, err, "could not save the image")
		return
	}
	h.respondWithKYC(w, r, driverID)
}

// DocumentContent handles GET /driver/kyc/documents/{kind}/content.
//
// On a backend that can sign URLs it redirects, so the image travels from
// object storage to the client without passing through this server; otherwise
// it streams the bytes. Either way the session is checked first — a stored
// document is never reachable without one.
func (h *DriverKYCHandler) DocumentContent(w http.ResponseWriter, r *http.Request) {
	kind := domain.DocumentKind(r.PathValue("kind"))
	url, body, err := h.svc.OpenDocument(r.Context(), userIDFrom(r.Context()), kind)
	if err != nil {
		h.writeKYCError(w, err, "could not load the image")
		return
	}

	if url != "" {
		// Temporary: the signed URL expires, so nothing may cache this hop.
		w.Header().Set("Cache-Control", "no-store")
		http.Redirect(w, r, url, http.StatusTemporaryRedirect)
		return
	}

	defer func() {
		if err := body.Close(); err != nil {
			slog.Error("kyc: closing document body", "error", err)
		}
	}()
	w.Header().Set("Content-Type", service.DocumentContentType)
	w.Header().Set("Cache-Control", "private, no-store")
	if _, err := io.Copy(w, body); err != nil {
		// Headers are already sent, so there's no status left to change —
		// record it and let the client see a truncated response.
		slog.Error("kyc: streaming document", "error", err)
	}
}

// StartDigiLocker handles POST /driver/kyc/digilocker: the DigiLocker page
// for the app to open, and the URL it ends on.
func (h *DriverKYCHandler) StartDigiLocker(w http.ResponseWriter, r *http.Request) {
	session, err := h.svc.StartDigiLocker(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		h.writeKYCError(w, err, "could not start DigiLocker")
		return
	}
	writeJSON(w, http.StatusOK, session)
}

// CompleteDigiLocker handles POST /driver/kyc/digilocker/complete, which the
// app calls when the driver comes back from DigiLocker.
func (h *DriverKYCHandler) CompleteDigiLocker(w http.ResponseWriter, r *http.Request) {
	kyc, err := h.svc.CompleteDigiLocker(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		h.writeKYCError(w, err, "could not read your DigiLocker result")
		return
	}
	writeJSON(w, http.StatusOK, kyc)
}

// VerifyDrivingLicense handles POST /driver/kyc/driving-license.
func (h *DriverKYCHandler) VerifyDrivingLicense(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Number string `json:"number"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	kyc, err := h.svc.VerifyDrivingLicense(r.Context(), userIDFrom(r.Context()), req.Number)
	if err != nil {
		h.writeKYCError(w, err, "could not check your licence")
		return
	}
	writeJSON(w, http.StatusOK, kyc)
}

// DigiLockerDone handles GET /kyc/digilocker/done, where DigiLocker sends the
// driver when they finish. The app reads the result itself; this page only
// tells the driver to go back to it.
func DigiLockerDone(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	io.WriteString(w, digiLockerDonePage)
}

const digiLockerDonePage = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DigiLocker done</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
font-family:system-ui,sans-serif;background:#E7F0F8;color:#0B2239;text-align:center;padding:16px}
h1{font-size:20px;margin:0 0 8px}p{margin:0;color:#4a5d70}
</style></head>
<body><div><h1>All done</h1><p>Close this page to go back to the MOJUD Driver app.</p></div></body></html>`

// Submit handles POST /driver/kyc/submit.
func (h *DriverKYCHandler) Submit(w http.ResponseWriter, r *http.Request) {
	kyc, err := h.svc.Submit(r.Context(), userIDFrom(r.Context()))
	if err != nil {
		h.writeKYCError(w, err, "could not submit your documents")
		return
	}
	writeJSON(w, http.StatusOK, kyc)
}

// respondWithKYC returns the whole Document View state after a write, so the
// app re-renders from one authoritative shape instead of patching its own.
func (h *DriverKYCHandler) respondWithKYC(w http.ResponseWriter, r *http.Request, driverID string) {
	kyc, err := h.svc.Load(r.Context(), driverID)
	if err != nil {
		h.writeKYCError(w, err, "could not load documents")
		return
	}
	writeJSON(w, http.StatusOK, kyc)
}

// writeKYCError maps a service or repository error onto a status and a
// machine-readable code. fallback is the message for anything unrecognised —
// those are logged and reported generically, never echoed to the client.
func (h *DriverKYCHandler) writeKYCError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, service.ErrInvalidProfile):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, service.ErrUnsupportedImage):
		writeErrorCode(w, http.StatusUnsupportedMediaType, "unsupported_image", err.Error(), 0)
	case errors.Is(err, service.ErrDocumentTooLarge):
		writeErrorCode(w, http.StatusRequestEntityTooLarge, "document_too_large",
			err.Error()+" (maximum "+strconv.Itoa(service.MaxDocumentBytes>>20)+" MB)", 0)
	case errors.Is(err, service.ErrUnknownDocumentKind):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, service.ErrKYCIncomplete):
		writeErrorCode(w, http.StatusConflict, "kyc_incomplete", err.Error(), 0)
	case errors.Is(err, repository.ErrAadhaarTaken):
		writeErrorCode(w, http.StatusConflict, "aadhaar_taken", err.Error(), 0)
	case errors.Is(err, service.ErrIdentityLocked):
		writeErrorCode(w, http.StatusConflict, "identity_locked", err.Error(), 0)
	case errors.Is(err, service.ErrVerificationUnavailable):
		writeErrorCode(w, http.StatusServiceUnavailable, "verification_unavailable", err.Error(), 0)
	case errors.Is(err, service.ErrTooManyChecks):
		writeErrorCode(w, http.StatusTooManyRequests, "too_many_attempts", err.Error(), 0)
	case errors.Is(err, service.ErrVerificationPending):
		writeErrorCode(w, http.StatusConflict, "verification_pending", err.Error(), 0)
	case errors.Is(err, service.ErrNoDigiLockerSession):
		writeErrorCode(w, http.StatusConflict, "no_digilocker_session", err.Error(), 0)
	case errors.Is(err, service.ErrVerificationFailed):
		writeErrorCode(w, http.StatusUnprocessableEntity, "verification_failed", err.Error(), 0)
	case errors.Is(err, service.ErrAadhaarMismatch):
		writeErrorCode(w, http.StatusUnprocessableEntity, "aadhaar_mismatch", err.Error(), 0)
	case errors.Is(err, service.ErrLicenseNotFound):
		writeErrorCode(w, http.StatusUnprocessableEntity, "license_not_found", err.Error(), 0)
	case errors.Is(err, service.ErrLicenseRejected):
		writeErrorCode(w, http.StatusUnprocessableEntity, "license_rejected", err.Error(), 0)
	case errors.Is(err, service.ErrBankAccountInvalid):
		writeErrorCode(w, http.StatusUnprocessableEntity, "bank_account_invalid", err.Error(), 0)
	case errors.Is(err, repository.ErrDocumentNotFound), errors.Is(err, storage.ErrNotFound):
		writeError(w, http.StatusNotFound, "document not found")
	case errors.Is(err, repository.ErrDriverNotFound):
		writeError(w, http.StatusNotFound, "driver not found")
	default:
		slog.Error("kyc: request failed", "error", err)
		writeError(w, http.StatusInternalServerError, fallback)
	}
}
