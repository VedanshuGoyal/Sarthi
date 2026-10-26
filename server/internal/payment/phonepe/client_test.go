package phonepe

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// fakePhonePe stands in for PhonePe's token and checkout endpoints.
type fakePhonePe struct {
	tokens    atomic.Int32
	lastForm  url.Values
	lastAuth  string
	lastOrder map[string]any
	status    string // order-status reply body
	rejectAPI atomic.Bool
}

func newFake(t *testing.T, f *fakePhonePe, now time.Time) *Client {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		n := f.tokens.Add(1)
		raw, _ := io.ReadAll(r.Body)
		f.lastForm, _ = url.ParseQuery(string(raw))
		_ = json.NewEncoder(w).Encode(map[string]any{
			"access_token": "tok-" + string(rune('0'+n)),
			"expires_at":   now.Add(time.Hour).Unix(),
			"token_type":   "O-Bearer",
		})
	})
	mux.HandleFunc("POST /checkout/v2/sdk/order", func(w http.ResponseWriter, r *http.Request) {
		f.lastAuth = r.Header.Get("Authorization")
		if f.rejectAPI.Load() {
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = io.WriteString(w, `{"code":"401"}`)
			return
		}
		_ = json.NewDecoder(r.Body).Decode(&f.lastOrder)
		_, _ = io.WriteString(w, `{"orderId":"OMO1","state":"PENDING","expireAt":1703756259307,"token":"order-token"}`)
	})
	mux.HandleFunc("GET /checkout/v2/order/{id}/status", func(w http.ResponseWriter, r *http.Request) {
		f.lastAuth = r.Header.Get("Authorization")
		_, _ = io.WriteString(w, f.status)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return New(Config{
		ClientID: "cid", ClientSecret: "secret", MerchantID: "M1",
		WebhookUsername: "hook", WebhookPassword: "pass",
	}, WithURLs(srv.URL+"/token", srv.URL), WithClock(func() time.Time { return now }))
}

func TestCreateOrderIsUPIOnlyAndReusesToken(t *testing.T) {
	f := &fakePhonePe{}
	c := newFake(t, f, time.Unix(1_700_000_000, 0))
	ctx := context.Background()

	order, err := c.CreateOrder(ctx, "MOJUD_abc_1", 45000, 15*time.Minute)
	if err != nil {
		t.Fatalf("CreateOrder: %v", err)
	}
	if order.ProviderOrderID != "OMO1" || order.Token != "order-token" {
		t.Fatalf("order = %+v", order)
	}
	if !order.ExpiresAt.Equal(time.UnixMilli(1703756259307)) {
		t.Errorf("ExpiresAt = %v", order.ExpiresAt)
	}
	if f.lastAuth != "O-Bearer tok-1" {
		t.Errorf("Authorization = %q", f.lastAuth)
	}
	if got := f.lastForm.Get("grant_type"); got != "client_credentials" {
		t.Errorf("grant_type = %q", got)
	}
	if got := f.lastForm.Get("client_version"); got != "1" {
		t.Errorf("client_version = %q", got)
	}
	if f.lastOrder["amount"] != float64(45000) || f.lastOrder["expireAfter"] != float64(900) {
		t.Errorf("order body = %v", f.lastOrder)
	}
	modes, _ := json.Marshal(f.lastOrder["paymentFlow"])
	if !strings.Contains(string(modes), "UPI_INTENT") || strings.Contains(string(modes), "CARD") {
		t.Errorf("payment modes = %s", modes)
	}

	if _, err := c.CreateOrder(ctx, "MOJUD_abc_2", 45000, 15*time.Minute); err != nil {
		t.Fatalf("second CreateOrder: %v", err)
	}
	if n := f.tokens.Load(); n != 1 {
		t.Errorf("token requests = %d, want 1 (cached)", n)
	}
}

func TestUnauthorisedReplyDropsToken(t *testing.T) {
	f := &fakePhonePe{}
	c := newFake(t, f, time.Unix(1_700_000_000, 0))
	ctx := context.Background()

	f.rejectAPI.Store(true)
	if _, err := c.CreateOrder(ctx, "MOJUD_x_1", 100, 5*time.Minute); err == nil {
		t.Fatal("CreateOrder succeeded on 401")
	}
	f.rejectAPI.Store(false)
	if _, err := c.CreateOrder(ctx, "MOJUD_x_2", 100, 5*time.Minute); err != nil {
		t.Fatalf("CreateOrder after 401: %v", err)
	}
	if n := f.tokens.Load(); n != 2 {
		t.Errorf("token requests = %d, want 2", n)
	}
}

func TestOrderStatusReadsThePayingAttempt(t *testing.T) {
	f := &fakePhonePe{status: `{
		"orderId":"OMO1","state":"COMPLETED","amount":45000,
		"paymentDetails":[
			{"transactionId":"T1","paymentMode":"UPI_COLLECT","state":"FAILED"},
			{"transactionId":"T2","paymentMode":"UPI_INTENT","state":"COMPLETED",
			 "splitInstruments":[{"rail":{"type":"UPI","utr":"412345678901"}}]}
		]}`}
	c := newFake(t, f, time.Unix(1_700_000_000, 0))

	st, err := c.OrderStatus(context.Background(), "MOJUD_abc_1")
	if err != nil {
		t.Fatalf("OrderStatus: %v", err)
	}
	want := domain.GatewayOrderStatus{State: domain.PaymentCompleted, AmountPaise: 45000,
		TransactionID: "T2", PaymentMode: "UPI_INTENT", UTR: "412345678901"}
	if st != want {
		t.Errorf("status = %+v, want %+v", st, want)
	}

	f.status = `{"state":"SOMETHING_NEW","amount":1}`
	if _, err := c.OrderStatus(context.Background(), "MOJUD_abc_1"); err == nil {
		t.Error("unknown state accepted")
	}
}

func TestVerifyWebhook(t *testing.T) {
	c := New(Config{WebhookUsername: "hook", WebhookPassword: "pass"})
	sum := sha256.Sum256([]byte("hook:pass"))
	good := hex.EncodeToString(sum[:])
	for _, tc := range []struct {
		header string
		want   bool
	}{
		{good, true},
		{strings.ToUpper(good), true},
		{"SHA256 " + good, true},
		{"", false},
		{good[:10], false},
	} {
		if got := c.VerifyWebhook(tc.header); got != tc.want {
			t.Errorf("VerifyWebhook(%q) = %v, want %v", tc.header, got, tc.want)
		}
	}
	if New(Config{}).VerifyWebhook(good) {
		t.Error("verified with no credentials configured")
	}
}

func TestWebhookOrder(t *testing.T) {
	id, err := WebhookOrder([]byte(`{"event":"checkout.order.completed","payload":{"merchantOrderId":"MOJUD_a_1","state":"COMPLETED"}}`))
	if err != nil || id != "MOJUD_a_1" {
		t.Fatalf("WebhookOrder = %q, %v", id, err)
	}
	if _, err := WebhookOrder([]byte(`{"event":"x","payload":{}}`)); err == nil {
		t.Error("accepted a webhook with no order id")
	}
}
