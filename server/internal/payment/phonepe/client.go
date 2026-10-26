// Package phonepe is an outbound adapter for PhonePe's payment gateway
// (Standard Checkout v2, mobile SDK flow):
//
//   - an OAuth client-credentials token, cached until shortly before PhonePe
//     says it expires;
//   - POST /checkout/v2/sdk/order — a new order and the token the customer
//     app's PhonePe SDK opens it with, limited to UPI (intent, collect, QR);
//   - GET /checkout/v2/order/{merchantOrderId}/status — the order's state,
//     which is the only thing the server ever treats as proof of payment;
//   - the webhook's Authorization header, SHA256(username:password).
//
// Docs: https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile
//
// It implements service.PaymentGateway.
package phonepe

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// Environment is PhonePe's name for where orders go; the app's SDK is
// initialised with the same string.
type Environment string

const (
	Sandbox    Environment = "SANDBOX"
	Production Environment = "PRODUCTION"
)

// Endpoints per environment.
const (
	sandboxTokenURL    = "https://api-preprod.phonepe.com/apis/pg-sandbox/v1/oauth/token"
	sandboxBaseURL     = "https://api-preprod.phonepe.com/apis/pg-sandbox"
	productionTokenURL = "https://api.phonepe.com/apis/identity-manager/v1/oauth/token"
	productionBaseURL  = "https://api.phonepe.com/apis/pg"
)

// tokenLeeway is how long before PhonePe's expires_at a cached token is
// replaced.
const tokenLeeway = 5 * time.Minute

// Config holds the credentials from PhonePe's business dashboard
// (Developer Settings).
type Config struct {
	ClientID      string
	ClientSecret  string
	ClientVersion string
	MerchantID    string
	Environment   Environment

	// WebhookUsername and WebhookPassword are what was entered when the
	// webhook was created; PhonePe sends SHA256(username:password).
	WebhookUsername string
	WebhookPassword string
}

// Client talks to PhonePe. Safe for concurrent use.
type Client struct {
	cfg      Config
	tokenURL string
	baseURL  string
	http     *http.Client
	now      func() time.Time

	// mu guards the cached token and is held across a refresh, so
	// concurrent callers share one token request.
	mu        sync.Mutex
	token     string
	refreshAt time.Time
}

// Option customises a Client (tests point it at an httptest server).
type Option func(*Client)

// WithURLs overrides the token endpoint and the API base URL.
func WithURLs(tokenURL, baseURL string) Option {
	return func(c *Client) { c.tokenURL, c.baseURL = tokenURL, baseURL }
}

// WithHTTPClient overrides the underlying http.Client.
func WithHTTPClient(h *http.Client) Option {
	return func(c *Client) { c.http = h }
}

// WithClock overrides the time source.
func WithClock(now func() time.Time) Option {
	return func(c *Client) { c.now = now }
}

// New builds a Client. An empty Environment means the sandbox and an empty
// ClientVersion "1".
func New(cfg Config, opts ...Option) *Client {
	if cfg.Environment == "" {
		cfg.Environment = Sandbox
	}
	if cfg.ClientVersion == "" {
		cfg.ClientVersion = "1"
	}
	c := &Client{
		cfg:      cfg,
		tokenURL: sandboxTokenURL,
		baseURL:  sandboxBaseURL,
		http:     &http.Client{Timeout: 15 * time.Second},
		now:      time.Now,
	}
	if cfg.Environment == Production {
		c.tokenURL, c.baseURL = productionTokenURL, productionBaseURL
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// Name is the provider the app's checkout is told to open.
func (c *Client) Name() string { return "phonepe" }

// MerchantID is the merchant the app's SDK is initialised with.
func (c *Client) MerchantID() string { return c.cfg.MerchantID }

// Environment is where orders go, as the app's SDK names it.
func (c *Client) Environment() string { return string(c.cfg.Environment) }

// upiOnly limits the checkout to UPI: the customer's UPI app (intent), a
// collect request to their UPI id, or a QR code.
var upiOnly = map[string]any{
	"type": "PG_CHECKOUT",
	"paymentModeConfig": map[string]any{
		"enabledPaymentModes": []map[string]string{
			{"type": "UPI_INTENT"},
			{"type": "UPI_COLLECT"},
			{"type": "UPI_QR"},
		},
	},
}

// createOrderResponse is the slice of the create-order reply we use.
type createOrderResponse struct {
	OrderID  string `json:"orderId"`
	Token    string `json:"token"`
	ExpireAt int64  `json:"expireAt"` // epoch milliseconds
}

// CreateOrder opens an order for amountPaise under merchantOrderID that
// expires after expireAfter (PhonePe accepts 5–60 minutes).
func (c *Client) CreateOrder(ctx context.Context, merchantOrderID string, amountPaise int64, expireAfter time.Duration) (domain.GatewayOrder, error) {
	body := map[string]any{
		"merchantOrderId": merchantOrderID,
		"amount":          amountPaise,
		"expireAfter":     int64(expireAfter / time.Second),
		"paymentFlow":     upiOnly,
	}
	var out createOrderResponse
	if err := c.call(ctx, http.MethodPost, "/checkout/v2/sdk/order", body, &out); err != nil {
		return domain.GatewayOrder{}, fmt.Errorf("phonepe: create order: %w", err)
	}
	if out.OrderID == "" || out.Token == "" {
		return domain.GatewayOrder{}, fmt.Errorf("phonepe: create order: reply carried no orderId/token")
	}
	expires := c.now().Add(expireAfter)
	if out.ExpireAt > 0 {
		expires = time.UnixMilli(out.ExpireAt)
	}
	return domain.GatewayOrder{ProviderOrderID: out.OrderID, Token: out.Token, ExpiresAt: expires}, nil
}

// orderStatusResponse is the slice of the order-status reply we use.
type orderStatusResponse struct {
	State          string `json:"state"`
	Amount         int64  `json:"amount"`
	PaymentDetails []struct {
		TransactionID    string `json:"transactionId"`
		PaymentMode      string `json:"paymentMode"`
		State            string `json:"state"`
		SplitInstruments []struct {
			Rail struct {
				UTR string `json:"utr"`
			} `json:"rail"`
		} `json:"splitInstruments"`
	} `json:"paymentDetails"`
}

// OrderStatus asks PhonePe where merchantOrderID stands.
func (c *Client) OrderStatus(ctx context.Context, merchantOrderID string) (domain.GatewayOrderStatus, error) {
	path := "/checkout/v2/order/" + url.PathEscape(merchantOrderID) + "/status?details=false"
	var out orderStatusResponse
	if err := c.call(ctx, http.MethodGet, path, nil, &out); err != nil {
		return domain.GatewayOrderStatus{}, fmt.Errorf("phonepe: order status: %w", err)
	}
	st := domain.GatewayOrderStatus{AmountPaise: out.Amount}
	switch out.State {
	case "COMPLETED":
		st.State = domain.PaymentCompleted
	case "FAILED":
		st.State = domain.PaymentFailed
	case "PENDING":
		st.State = domain.PaymentPending
	default:
		return domain.GatewayOrderStatus{}, fmt.Errorf("phonepe: order status: unknown state %q", out.State)
	}
	// The attempt that paid, else the latest one.
	for i := len(out.PaymentDetails) - 1; i >= 0; i-- {
		d := out.PaymentDetails[i]
		if st.TransactionID == "" || d.State == "COMPLETED" {
			st.TransactionID, st.PaymentMode = d.TransactionID, d.PaymentMode
			st.UTR = ""
			for _, si := range d.SplitInstruments {
				if si.Rail.UTR != "" {
					st.UTR = si.Rail.UTR
					break
				}
			}
		}
		if d.State == "COMPLETED" {
			break
		}
	}
	return st, nil
}

// VerifyWebhook reports whether authorization — the webhook's Authorization
// header — is SHA256(username:password) of the configured credentials. With
// none configured, nothing verifies.
func (c *Client) VerifyWebhook(authorization string) bool {
	if c.cfg.WebhookUsername == "" || c.cfg.WebhookPassword == "" {
		return false
	}
	sum := sha256.Sum256([]byte(c.cfg.WebhookUsername + ":" + c.cfg.WebhookPassword))
	want := hex.EncodeToString(sum[:])
	got := strings.ToLower(strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(authorization), "SHA256")))
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// WebhookOrder pulls the merchant order id out of a webhook body. Nothing
// else in it is trusted: the caller re-reads the order from PhonePe.
func WebhookOrder(body []byte) (string, error) {
	var hook struct {
		Event   string `json:"event"`
		Payload struct {
			MerchantOrderID string `json:"merchantOrderId"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(body, &hook); err != nil {
		return "", fmt.Errorf("phonepe: webhook: %w", err)
	}
	if hook.Payload.MerchantOrderID == "" {
		return "", fmt.Errorf("phonepe: webhook %q names no merchantOrderId", hook.Event)
	}
	return hook.Payload.MerchantOrderID, nil
}

// call sends one authorised API request and decodes a 2xx JSON reply into out.
func (c *Client) call(ctx context.Context, method, path string, body, out any) error {
	token, err := c.accessToken(ctx)
	if err != nil {
		return err
	}
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encode request: %w", err)
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "O-Bearer "+token)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 256<<10))
	if err != nil {
		return fmt.Errorf("read reply: %w", err)
	}
	if resp.StatusCode == http.StatusUnauthorized {
		// A token PhonePe no longer honours: drop it so the next call mints one.
		c.mu.Lock()
		c.token = ""
		c.mu.Unlock()
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("decode reply: %w", err)
	}
	return nil
}

// tokenResponse is the slice of PhonePe's OAuth reply we use.
type tokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresAt   int64  `json:"expires_at"` // epoch seconds
}

// accessToken returns the cached token while it has more than tokenLeeway
// left, else fetches a new one. A failed fetch isn't cached.
func (c *Client) accessToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token != "" && c.now().Before(c.refreshAt) {
		return c.token, nil
	}
	form := url.Values{
		"client_id":      {c.cfg.ClientID},
		"client_version": {c.cfg.ClientVersion},
		"client_secret":  {c.cfg.ClientSecret},
		"grant_type":     {"client_credentials"},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("phonepe: build token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	issuedAt := c.now()
	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("phonepe: token request: %w", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return "", fmt.Errorf("phonepe: read token reply: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", fmt.Errorf("phonepe: token request failed: status %d: %s",
			resp.StatusCode, strings.TrimSpace(string(raw)))
	}
	var tr tokenResponse
	if err := json.Unmarshal(raw, &tr); err != nil {
		return "", fmt.Errorf("phonepe: decode token reply: %w", err)
	}
	if tr.AccessToken == "" {
		return "", fmt.Errorf("phonepe: token reply carried no access_token")
	}
	expires := issuedAt.Add(time.Hour)
	if tr.ExpiresAt > 0 {
		expires = time.Unix(tr.ExpiresAt, 0)
	}
	// Refresh tokenLeeway early — or halfway, for a short-lived token.
	leeway := min(tokenLeeway, expires.Sub(issuedAt)/2)
	c.token, c.refreshAt = tr.AccessToken, expires.Add(-leeway)
	return c.token, nil
}
