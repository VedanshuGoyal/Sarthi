package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/sarthi/server/internal/service"
)

// HUMAN REVIEW REQUIRED: payments. The app branches on these codes; a
// payment still going through must not read as a gateway failure.
func TestWritePaymentError_codes(t *testing.T) {
	for _, tc := range []struct {
		err    error
		status int
		code   string
	}{
		{service.ErrAlreadyPaid, http.StatusConflict, "already_paid"},
		{fmt.Errorf("checkout: %w", service.ErrPaymentUnderway), http.StatusConflict, "payment_underway"},
		{service.ErrPaymentsOff, http.StatusServiceUnavailable, "payments_not_configured"},
	} {
		rec := httptest.NewRecorder()
		writePaymentError(rec, tc.err, "")
		var body errorResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("%v: body %q: %v", tc.err, rec.Body, err)
		}
		if rec.Code != tc.status || body.Code != tc.code {
			t.Errorf("%v: %d %q, want %d %q", tc.err, rec.Code, body.Code, tc.status, tc.code)
		}
	}
}
