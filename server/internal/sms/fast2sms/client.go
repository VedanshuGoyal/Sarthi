// Package fast2sms is an outbound adapter for the Fast2SMS managed-OTP API
// (https://docs.fast2sms.com/reference/send-otp). Fast2SMS generates, stores,
// and expires the one-time code itself, so the backend keeps no OTP state — it
// asks Fast2SMS to send a code, then asks Fast2SMS whether a submitted code is
// valid. This satisfies the "no Redis / nothing to persist for OTPs" stance.
//
// It implements service.OTPSender. Numbers are passed in as bare 10-digit
// national mobile numbers (Fast2SMS is India-only and rejects the +91 prefix).
package fast2sms

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// defaultBaseURL is the Fast2SMS developer API root. Endpoints hang off it as
// /otp/send, /otp/verify and /otp/resend.
const defaultBaseURL = "https://www.fast2sms.com/dev"

// Client talks to the Fast2SMS OTP endpoints.
type Client struct {
	apiKey  string
	otpID   string
	baseURL string
	http    *http.Client
}

// Option customises a Client (used mainly by tests to point at an httptest
// server or inject an http.Client).
type Option func(*Client)

// WithBaseURL overrides the API root (default [defaultBaseURL]).
func WithBaseURL(u string) Option {
	return func(c *Client) { c.baseURL = strings.TrimRight(u, "/") }
}

// WithHTTPClient overrides the underlying http.Client.
func WithHTTPClient(h *http.Client) Option {
	return func(c *Client) { c.http = h }
}

// New builds a Client. apiKey is the Fast2SMS Authorization key; otpID is the
// pre-registered OTP template identifier used when sending a new code.
func New(apiKey, otpID string, opts ...Option) *Client {
	c := &Client{
		apiKey:  apiKey,
		otpID:   otpID,
		baseURL: defaultBaseURL,
		http:    &http.Client{Timeout: 10 * time.Second},
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// SendOTP asks Fast2SMS to generate and text a fresh OTP to mobile.
func (c *Client) SendOTP(ctx context.Context, mobile string) error {
	resp, err := c.do(ctx, "/otp/send", map[string]any{
		"mobile": mobile,
		"otp_id": c.otpID,
	})
	if err != nil {
		return err
	}
	if !resp.ok {
		return fmt.Errorf("fast2sms: send otp failed: %s", resp.describe())
	}
	return nil
}

// ResendOTP asks Fast2SMS to re-text the last OTP sent to mobile. Fast2SMS
// enforces its own resend window and attempt cap.
func (c *Client) ResendOTP(ctx context.Context, mobile string) error {
	resp, err := c.do(ctx, "/otp/resend", map[string]any{
		"mobile": mobile,
	})
	if err != nil {
		return err
	}
	if !resp.ok {
		return fmt.Errorf("fast2sms: resend otp failed: %s", resp.describe())
	}
	return nil
}

// VerifyOTP reports whether code is the valid, unexpired OTP for mobile. A
// wrong, expired, or already-used code is a normal negative result (ok=false,
// err=nil); a non-nil error means the provider itself could not be reached or
// rejected our credentials.
func (c *Client) VerifyOTP(ctx context.Context, mobile, code string) (ok bool, err error) {
	resp, err := c.do(ctx, "/otp/verify", map[string]any{
		"mobile": mobile,
		"otp":    code,
	})
	if err != nil {
		return false, err
	}
	switch {
	case resp.ok:
		return true, nil
	// A definitive "not valid" from the provider is a normal negative, not our
	// error: 400 (invalid/expired/max attempts), 404 (no pending OTP), or an
	// explicit {"return": false}.
	case resp.status == http.StatusBadRequest,
		resp.status == http.StatusNotFound,
		resp.ret != nil && !*resp.ret:
		return false, nil
	default:
		// Ambiguous failure: transport error, 401 auth, 5xx, unparseable body.
		return false, fmt.Errorf("fast2sms: verify otp failed: %s", resp.describe())
	}
}

// apiResponse is a decoded Fast2SMS reply. The endpoints share a shape:
// {"return": bool, "message": ...}. We treat a 2xx status with a non-false
// "return" as success and key everything else off the HTTP status.
type apiResponse struct {
	status int
	ok     bool
	body   []byte
	ret    *bool
	// message is the provider's human message, if present.
	message string
}

// describe renders a compact diagnostic string for error messages.
func (r apiResponse) describe() string {
	if r.message != "" {
		return fmt.Sprintf("status %d: %s", r.status, r.message)
	}
	return fmt.Sprintf("status %d: %s", r.status, strings.TrimSpace(string(r.body)))
}

// do POSTs payload as JSON to baseURL+path with the Authorization header and
// decodes the reply.
func (c *Client) do(ctx context.Context, path string, payload map[string]any) (apiResponse, error) {
	buf, err := json.Marshal(payload)
	if err != nil {
		return apiResponse{}, fmt.Errorf("fast2sms: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(buf))
	if err != nil {
		return apiResponse{}, fmt.Errorf("fast2sms: build request: %w", err)
	}
	req.Header.Set("Authorization", c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	httpResp, err := c.http.Do(req)
	if err != nil {
		return apiResponse{}, fmt.Errorf("fast2sms: request %s: %w", path, err)
	}
	defer httpResp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(httpResp.Body, 1<<20))
	if err != nil {
		return apiResponse{}, fmt.Errorf("fast2sms: read response: %w", err)
	}

	resp := apiResponse{status: httpResp.StatusCode, body: body}

	// The body is best-effort JSON; a decode failure doesn't override the
	// authoritative HTTP status.
	var decoded struct {
		Return  *bool           `json:"return"`
		Message json.RawMessage `json:"message"`
	}
	if json.Unmarshal(body, &decoded) == nil {
		resp.ret = decoded.Return
		resp.message = flattenMessage(decoded.Message)
	}

	// Success = 2xx and the provider didn't explicitly signal return:false.
	resp.ok = httpResp.StatusCode >= 200 && httpResp.StatusCode < 300 &&
		(resp.ret == nil || *resp.ret)
	return resp, nil
}

// flattenMessage renders Fast2SMS's "message" field, which is sometimes a
// string and sometimes an array of strings.
func flattenMessage(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var s string
	if json.Unmarshal(raw, &s) == nil {
		return s
	}
	var list []string
	if json.Unmarshal(raw, &list) == nil {
		return strings.Join(list, "; ")
	}
	return strings.TrimSpace(string(raw))
}
