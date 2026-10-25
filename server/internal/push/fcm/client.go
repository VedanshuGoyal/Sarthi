// Package fcm sends push notifications through the Firebase Cloud Messaging
// HTTP v1 API (https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages).
//
// It authenticates as a Firebase service account: the JSON key downloaded
// from the Firebase console (Project settings → Service accounts). Access
// tokens are minted from it with the OAuth 2.0 JWT-bearer flow and reused
// until they expire, so a send costs one HTTP request.
//
// It implements push.Sender.
package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/jwt"

	"github.com/sarthi/server/internal/push"
)

const (
	defaultBaseURL  = "https://fcm.googleapis.com"
	defaultTokenURL = "https://oauth2.googleapis.com/token"
	messagingScope  = "https://www.googleapis.com/auth/firebase.messaging"
)

// Client sends messages for one Firebase project.
type Client struct {
	http      *http.Client
	baseURL   string
	projectID string
}

// Option configures a Client.
type Option func(*Client)

// WithBaseURL points the client at another FCM endpoint (tests).
func WithBaseURL(u string) Option {
	return func(c *Client) { c.baseURL = strings.TrimRight(u, "/") }
}

// serviceAccount is the part of a Google service-account key file we read.
type serviceAccount struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
	TokenURI    string `json:"token_uri"`
}

// New builds a client from a service-account key file's contents. The
// Firebase project is the one the key belongs to.
func New(credentialsJSON []byte, opts ...Option) (*Client, error) {
	var sa serviceAccount
	if err := json.Unmarshal(credentialsJSON, &sa); err != nil {
		return nil, fmt.Errorf("fcm: reading service account key: %w", err)
	}
	if sa.Type != "service_account" || sa.ProjectID == "" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("fcm: not a service account key (want type, project_id, client_email, private_key)")
	}
	tokenURL := sa.TokenURI
	if tokenURL == "" {
		tokenURL = defaultTokenURL
	}
	conf := &jwt.Config{
		Email:      sa.ClientEmail,
		PrivateKey: []byte(sa.PrivateKey),
		Scopes:     []string{messagingScope},
		TokenURL:   tokenURL,
	}

	// The token source's context only carries the HTTP client used to mint
	// tokens; per-send cancellation comes from each request's own context.
	base := &http.Client{Timeout: 10 * time.Second}
	tokenCtx := context.WithValue(context.Background(), oauth2.HTTPClient, base)
	c := &Client{
		http:      oauth2.NewClient(tokenCtx, conf.TokenSource(tokenCtx)),
		baseURL:   defaultBaseURL,
		projectID: sa.ProjectID,
	}
	c.http.Timeout = 10 * time.Second
	for _, o := range opts {
		o(c)
	}
	return c, nil
}

// ProjectID is the Firebase project messages are sent through.
func (c *Client) ProjectID() string { return c.projectID }

// Wire format — only the fields we set.
type sendRequest struct {
	Message message `json:"message"`
}

type message struct {
	Token        string            `json:"token"`
	Notification notification      `json:"notification"`
	Data         map[string]string `json:"data,omitempty"`
	Android      androidConfig     `json:"android"`
}

type notification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type androidConfig struct {
	// HIGH wakes a dozing phone so the notification shows straight away.
	Priority     string              `json:"priority"`
	TTL          string              `json:"ttl,omitempty"`
	Notification androidNotification `json:"notification"`
}

type androidNotification struct {
	ChannelID             string `json:"channel_id,omitempty"`
	Tag                   string `json:"tag,omitempty"`
	DefaultSound          bool   `json:"default_sound"`
	DefaultVibrateTimings bool   `json:"default_vibrate_timings"`
	NotificationPriority  string `json:"notification_priority"`
	Visibility            string `json:"visibility"`
}

type errorBody struct {
	Error struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
		Details []struct {
			ErrorCode string `json:"errorCode"`
		} `json:"details"`
	} `json:"error"`
}

// Send delivers m. It returns push.ErrUnregistered when FCM says the token is
// gone or was never this project's, so the caller can drop it.
func (c *Client) Send(ctx context.Context, m push.Message) error {
	req := sendRequest{Message: message{
		Token:        m.Token,
		Notification: notification{Title: m.Title, Body: m.Body},
		Data:         m.Data,
		Android: androidConfig{
			Priority: "HIGH",
			Notification: androidNotification{
				ChannelID:             m.Channel,
				Tag:                   m.Tag,
				DefaultSound:          true,
				DefaultVibrateTimings: true,
				NotificationPriority:  "PRIORITY_HIGH",
				Visibility:            "PUBLIC",
			},
		},
	}}
	if m.TTL > 0 {
		req.Message.Android.TTL = fmt.Sprintf("%ds", int(m.TTL.Seconds()))
	}
	payload, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("fcm: encoding message: %w", err)
	}

	url := fmt.Sprintf("%s/v1/projects/%s/messages:send", c.baseURL, c.projectID)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("fcm: building request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(httpReq)
	if err != nil {
		return fmt.Errorf("fcm: sending: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode == http.StatusOK {
		return nil
	}

	var e errorBody
	_ = json.Unmarshal(body, &e)
	for _, d := range e.Error.Details {
		switch d.ErrorCode {
		case "UNREGISTERED", "SENDER_ID_MISMATCH":
			return push.ErrUnregistered
		}
	}
	// A token that was never valid comes back as a plain bad argument.
	if e.Error.Status == "INVALID_ARGUMENT" && strings.Contains(strings.ToLower(e.Error.Message), "registration token") {
		return push.ErrUnregistered
	}
	return fmt.Errorf("fcm: %d %s: %s", resp.StatusCode, e.Error.Status, e.Error.Message)
}
