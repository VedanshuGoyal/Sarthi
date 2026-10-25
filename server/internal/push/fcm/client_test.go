package fcm

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/push"
)

// fakeGoogle serves both the OAuth token endpoint and the FCM send endpoint.
func fakeGoogle(t *testing.T, send http.HandlerFunc) (*httptest.Server, *int) {
	t.Helper()
	tokens := 0
	mux := http.NewServeMux()
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		tokens++
		_ = r.ParseForm()
		if r.Form.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || r.Form.Get("assertion") == "" {
			http.Error(w, "bad grant", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"access_token":"tok-123","token_type":"Bearer","expires_in":3600}`)
	})
	mux.HandleFunc("POST /v1/projects/sarthi-test/messages:send", send)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv, &tokens
}

func serviceAccountJSON(t *testing.T, tokenURL string) []byte {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	b, _ := json.Marshal(map[string]string{
		"type":         "service_account",
		"project_id":   "sarthi-test",
		"private_key":  string(pemKey),
		"client_email": "push@sarthi-test.iam.gserviceaccount.com",
		"token_uri":    tokenURL,
	})
	return b
}

func TestSendBuildsAndAuthorizesMessage(t *testing.T) {
	var got sendRequest
	var auth string
	srv, tokens := fakeGoogle(t, func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&got)
		_, _ = io.WriteString(w, `{"name":"projects/sarthi-test/messages/1"}`)
	})
	c, err := New(serviceAccountJSON(t, srv.URL+"/token"), WithBaseURL(srv.URL))
	if err != nil {
		t.Fatal(err)
	}

	m := push.Message{
		Token: "device-1", Title: "New ride request", Body: "Round trip",
		Channel: "ride_requests", Tag: "ride-9",
		Data: map[string]string{"type": "ride_request", "rideId": "ride-9"},
		TTL:  90 * time.Minute,
	}
	for range 2 {
		if err := c.Send(context.Background(), m); err != nil {
			t.Fatalf("Send: %v", err)
		}
	}

	if auth != "Bearer tok-123" {
		t.Errorf("Authorization = %q", auth)
	}
	if *tokens != 1 {
		t.Errorf("minted %d access tokens for two sends, want 1 (reuse)", *tokens)
	}
	msg := got.Message
	if msg.Token != "device-1" || msg.Notification.Title != "New ride request" || msg.Data["rideId"] != "ride-9" {
		t.Errorf("message = %+v", msg)
	}
	if msg.Android.Priority != "HIGH" || msg.Android.TTL != "5400s" ||
		msg.Android.Notification.ChannelID != "ride_requests" || msg.Android.Notification.Tag != "ride-9" {
		t.Errorf("android = %+v", msg.Android)
	}
}

func TestSendMapsGoneTokensToErrUnregistered(t *testing.T) {
	cases := map[string]struct {
		status int
		body   string
		gone   bool
	}{
		"unregistered":    {404, `{"error":{"code":404,"status":"NOT_FOUND","message":"Requested entity was not found.","details":[{"errorCode":"UNREGISTERED"}]}}`, true},
		"other project":   {403, `{"error":{"code":403,"status":"PERMISSION_DENIED","message":"SenderId mismatch","details":[{"errorCode":"SENDER_ID_MISMATCH"}]}}`, true},
		"malformed token": {400, `{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"The registration token is not a valid FCM registration token"}}`, true},
		"server error":    {503, `{"error":{"code":503,"status":"UNAVAILABLE","message":"try later"}}`, false},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			srv, _ := fakeGoogle(t, func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(tc.status)
				_, _ = io.WriteString(w, tc.body)
			})
			c, err := New(serviceAccountJSON(t, srv.URL+"/token"), WithBaseURL(srv.URL))
			if err != nil {
				t.Fatal(err)
			}
			err = c.Send(context.Background(), push.Message{Token: "x"})
			if errors.Is(err, push.ErrUnregistered) != tc.gone {
				t.Fatalf("err = %v, want unregistered=%v", err, tc.gone)
			}
			if err == nil {
				t.Fatal("want an error")
			}
		})
	}
}

func TestNewRejectsNonServiceAccount(t *testing.T) {
	for _, in := range []string{`not json`, `{"type":"authorized_user"}`, `{"type":"service_account","project_id":"p"}`} {
		if _, err := New([]byte(in)); err == nil || !strings.HasPrefix(err.Error(), "fcm:") {
			t.Errorf("New(%s) err = %v", in, err)
		}
	}
}
