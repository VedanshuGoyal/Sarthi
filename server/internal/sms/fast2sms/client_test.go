package fast2sms

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// newTestClient points a Client at an httptest server and captures the last
// request path + decoded body for assertions.
func newTestClient(t *testing.T, status int, body string) (*Client, *capturedRequest) {
	t.Helper()
	cap := &capturedRequest{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cap.path = r.URL.Path
		cap.auth = r.Header.Get("Authorization")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &cap.body)
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(srv.Close)
	return New("secret-key", "otp-template", WithBaseURL(srv.URL)), cap
}

type capturedRequest struct {
	path string
	auth string
	body map[string]any
}

func TestSendOTP(t *testing.T) {
	c, cap := newTestClient(t, http.StatusOK, `{"return":true,"message":["OTP sent"]}`)

	if err := c.SendOTP(context.Background(), "9876543210"); err != nil {
		t.Fatalf("SendOTP: %v", err)
	}
	if cap.path != "/otp/send" {
		t.Fatalf("path = %q, want /otp/send", cap.path)
	}
	if cap.auth != "secret-key" {
		t.Fatalf("Authorization = %q, want secret-key", cap.auth)
	}
	if cap.body["mobile"] != "9876543210" || cap.body["otp_id"] != "otp-template" {
		t.Fatalf("body = %v", cap.body)
	}
}

func TestSendOTP_ProviderError(t *testing.T) {
	c, _ := newTestClient(t, http.StatusUnauthorized, `{"return":false,"message":"Invalid Authentication"}`)
	if err := c.SendOTP(context.Background(), "9876543210"); err == nil {
		t.Fatal("expected an error on 401")
	}
}

func TestResendOTP(t *testing.T) {
	c, cap := newTestClient(t, http.StatusOK, `{"return":true}`)
	if err := c.ResendOTP(context.Background(), "9876543210"); err != nil {
		t.Fatalf("ResendOTP: %v", err)
	}
	if cap.path != "/otp/resend" {
		t.Fatalf("path = %q, want /otp/resend", cap.path)
	}
	if _, ok := cap.body["otp_id"]; ok {
		t.Fatalf("resend must not send otp_id: %v", cap.body)
	}
}

func TestVerifyOTP(t *testing.T) {
	tests := []struct {
		name    string
		status  int
		body    string
		wantOK  bool
		wantErr bool
	}{
		{"valid", http.StatusOK, `{"return":true}`, true, false},
		{"return false on 200", http.StatusOK, `{"return":false,"message":"mismatch"}`, false, false},
		{"invalid code (400)", http.StatusBadRequest, `{"return":false,"message":"Invalid OTP"}`, false, false},
		{"no pending otp (404)", http.StatusNotFound, `{"return":false}`, false, false},
		{"provider outage (500)", http.StatusInternalServerError, `oops`, false, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, cap := newTestClient(t, tt.status, tt.body)
			ok, err := c.VerifyOTP(context.Background(), "9876543210", "654321")
			if tt.wantErr != (err != nil) {
				t.Fatalf("err = %v, wantErr = %v", err, tt.wantErr)
			}
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if !tt.wantErr && (cap.path != "/otp/verify" || cap.body["otp"] != "654321") {
				t.Fatalf("unexpected request: path=%q body=%v", cap.path, cap.body)
			}
		})
	}
}
