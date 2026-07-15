// Package api is the HTTP transport layer: it decodes requests, calls services,
// and encodes responses. It holds no business logic.
package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
)

// writeJSON encodes v as JSON with the given status code.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("encoding response", "error", err)
	}
}

// errorResponse is the shape of every error body. Code is a stable,
// machine-readable tag clients can branch on (empty for generic errors);
// RetryAfterSeconds accompanies rate-limit errors.
type errorResponse struct {
	Error             string `json:"error"`
	Code              string `json:"code,omitempty"`
	RetryAfterSeconds int    `json:"retryAfterSeconds,omitempty"`
}

// writeError sends a JSON error body with the given status and message.
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}

// writeErrorCode sends a JSON error carrying a machine-readable code. A
// positive retryAfter (seconds) is also surfaced as a Retry-After header.
func writeErrorCode(w http.ResponseWriter, status int, code, message string, retryAfter int) {
	if retryAfter > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
	}
	writeJSON(w, status, errorResponse{
		Error:             message,
		Code:              code,
		RetryAfterSeconds: retryAfter,
	})
}

// decodeJSON reads a JSON request body into dst, rejecting unknown fields.
func decodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}
