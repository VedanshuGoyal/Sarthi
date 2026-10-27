// Package surepass is an outbound adapter for Surepass's KYC APIs:
//
//   - DigiLocker, by link: POST /api/v1/digilocker/initialize opens a
//     session and returns the page the driver signs in on;
//     GET /api/v1/digilocker/status/{client_id} says whether they finished;
//     GET /api/v1/digilocker/download-aadhaar/{client_id} reads the Aadhaar.
//   - Driving licence: POST /api/v1/driving-license/driving-license looks a
//     licence up by number and date of birth.
//   - Bank account: POST /api/v1/bank-verification does a penny drop.
//
// Docs: https://app.surepass.app/docs/kyc (behind a console login).
// Production only answers from whitelisted IPs (the VPS).
//
// It implements service.IdentityVerifier.
package surepass

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// ProductionBaseURL is Surepass's production API.
const ProductionBaseURL = "https://kyc-api.surepass.app"

// digiLockerMinutes is how long a DigiLocker link stays usable.
const digiLockerMinutes = 10

// Client talks to Surepass. Safe for concurrent use.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
	now     func() time.Time
}

// Option customises a Client (tests point it at an httptest server).
type Option func(*Client)

// WithHTTPClient overrides the underlying http.Client.
func WithHTTPClient(h *http.Client) Option {
	return func(c *Client) { c.http = h }
}

// WithClock overrides the time source.
func WithClock(now func() time.Time) Option {
	return func(c *Client) { c.now = now }
}

// New builds a Client for the API at baseURL (empty means production),
// authenticating with the bearer token from Surepass's console.
func New(baseURL, token string, opts ...Option) *Client {
	if baseURL == "" {
		baseURL = ProductionBaseURL
	}
	c := &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		// Licence lookups and penny drops wait on government and bank
		// systems; Surepass itself allows them tens of seconds.
		http: &http.Client{Timeout: 45 * time.Second},
		now:  time.Now,
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// errNoRecord is a 404/422 reply: Surepass answered, and there is no such
// record (or the inputs don't match one).
var errNoRecord = errors.New("surepass: no matching record")

// StartDigiLocker opens a DigiLocker session that ends on redirectURL.
func (c *Client) StartDigiLocker(ctx context.Context, redirectURL string) (domain.DigiLockerSession, error) {
	body := map[string]any{"data": map[string]any{
		// New DigiLocker users can sign up on the way; existing ones sign in.
		"signup_flow":      true,
		"redirect_url":     redirectURL,
		"skip_main_screen": false,
		"expiry_minutes":   digiLockerMinutes,
	}}
	var out struct {
		ClientID      string  `json:"client_id"`
		URL           string  `json:"url"`
		ExpirySeconds float64 `json:"expiry_seconds"`
	}
	if err := c.call(ctx, http.MethodPost, "/api/v1/digilocker/initialize", body, &out); err != nil {
		return domain.DigiLockerSession{}, fmt.Errorf("surepass: digilocker initialize: %w", err)
	}
	if out.ClientID == "" || out.URL == "" {
		return domain.DigiLockerSession{}, errors.New("surepass: digilocker initialize: reply carried no client_id/url")
	}
	ttl := time.Duration(out.ExpirySeconds * float64(time.Second))
	if ttl <= 0 {
		ttl = digiLockerMinutes * time.Minute
	}
	return domain.DigiLockerSession{ClientID: out.ClientID, URL: out.URL, ExpiresAt: c.now().Add(ttl)}, nil
}

// DigiLockerStatus says whether the driver finished DigiLocker. A session
// Surepass no longer knows counts as failed.
func (c *Client) DigiLockerStatus(ctx context.Context, clientID string) (domain.DigiLockerState, error) {
	var out struct {
		Status    string `json:"status"`
		Completed bool   `json:"completed"`
		Failed    bool   `json:"failed"`
	}
	err := c.call(ctx, http.MethodGet, "/api/v1/digilocker/status/"+url.PathEscape(clientID), nil, &out)
	switch {
	case errors.Is(err, errNoRecord):
		return domain.DigiLockerFailed, nil
	case err != nil:
		return "", fmt.Errorf("surepass: digilocker status: %w", err)
	case out.Failed:
		return domain.DigiLockerFailed, nil
	case out.Completed:
		return domain.DigiLockerCompleted, nil
	}
	return domain.DigiLockerPending, nil
}

// aadhaarDetails is the slice of a DigiLocker Aadhaar we read; the XML
// section and DigiLocker's own metadata both carry it.
type aadhaarDetails struct {
	FullName      string `json:"full_name"`
	Name          string `json:"name"`
	DOB           string `json:"dob"`
	Gender        string `json:"gender"`
	MaskedAadhaar string `json:"masked_aadhaar"`
}

// DigiLockerAadhaar reads the Aadhaar from a completed session.
func (c *Client) DigiLockerAadhaar(ctx context.Context, clientID string) (domain.AadhaarRecord, error) {
	var out struct {
		XML      aadhaarDetails `json:"aadhaar_xml_data"`
		Metadata aadhaarDetails `json:"digilocker_metadata"`
	}
	path := "/api/v1/digilocker/download-aadhaar/" + url.PathEscape(clientID)
	if err := c.call(ctx, http.MethodGet, path, nil, &out); err != nil {
		return domain.AadhaarRecord{}, fmt.Errorf("surepass: download aadhaar: %w", err)
	}

	name := firstNonEmpty(out.XML.FullName, out.Metadata.Name)
	dob, err := parseDate(firstNonEmpty(out.XML.DOB, out.Metadata.DOB))
	if err != nil || name == "" {
		return domain.AadhaarRecord{}, errors.New("surepass: download aadhaar: reply carried no name/date of birth")
	}
	masked := strings.TrimSpace(out.XML.MaskedAadhaar)
	var last4 string
	if len(masked) >= 4 {
		last4 = masked[len(masked)-4:]
	}
	return domain.AadhaarRecord{
		Name:        strings.TrimSpace(name),
		DateOfBirth: dob,
		Gender:      gender(firstNonEmpty(out.XML.Gender, out.Metadata.Gender)),
		Last4:       last4,
	}, nil
}

// DrivingLicense looks a licence up. found is false when the transport
// department has no licence with that number and date of birth.
func (c *Client) DrivingLicense(ctx context.Context, number string, dob time.Time) (rec domain.LicenseRecord, found bool, err error) {
	body := map[string]any{"id_number": number, "dob": dob.Format(time.DateOnly)}
	var out struct {
		LicenseNumber string `json:"license_number"`
		Name          string `json:"name"`
		DOE           string `json:"doe"`
		TransportDOE  string `json:"transport_doe"`
		Classes       []any  `json:"vehicle_classes"`
	}
	err = c.call(ctx, http.MethodPost, "/api/v1/driving-license/driving-license", body, &out)
	if errors.Is(err, errNoRecord) {
		return domain.LicenseRecord{}, false, nil
	}
	if err != nil {
		return domain.LicenseRecord{}, false, fmt.Errorf("surepass: driving licence: %w", err)
	}

	rec = domain.LicenseRecord{
		Number: firstNonEmpty(out.LicenseNumber, number),
		Name:   strings.TrimSpace(out.Name),
	}
	// The later of the two expiries; 1800-01-01 is Surepass's "none".
	for _, s := range []string{out.DOE, out.TransportDOE} {
		if d, err := parseDate(s); err == nil && d.Year() > 1900 && d.After(rec.ValidUntil) {
			rec.ValidUntil = d
		}
	}
	for _, v := range out.Classes {
		if s, ok := v.(string); ok && strings.TrimSpace(s) != "" {
			rec.Classes = append(rec.Classes, strings.TrimSpace(s))
		}
	}
	return rec, true, nil
}

// BankAccount runs a penny drop on an account.
func (c *Client) BankAccount(ctx context.Context, number, ifsc string) (domain.BankAccountRecord, error) {
	body := map[string]any{"id_number": number, "ifsc": ifsc, "ifsc_details": false}
	var out struct {
		AccountExists bool   `json:"account_exists"`
		FullName      string `json:"full_name"`
	}
	err := c.call(ctx, http.MethodPost, "/api/v1/bank-verification", body, &out)
	if errors.Is(err, errNoRecord) {
		return domain.BankAccountRecord{}, nil
	}
	if err != nil {
		return domain.BankAccountRecord{}, fmt.Errorf("surepass: bank verification: %w", err)
	}
	return domain.BankAccountRecord{Exists: out.AccountExists, Name: strings.TrimSpace(out.FullName)}, nil
}

// envelope is how every Surepass reply is wrapped.
type envelope struct {
	Data        json.RawMessage `json:"data"`
	StatusCode  int             `json:"status_code"`
	Success     bool            `json:"success"`
	Message     string          `json:"message"`
	MessageCode string          `json:"message_code"`
}

// call sends a request and decodes the reply's data into out. 404 and 422
// come back as errNoRecord; anything else non-2xx is an error naming
// Surepass's message code.
func (c *Client) call(ctx context.Context, method, path string, body, out any) error {
	var reader io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(buf)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return err
	}

	var env envelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return fmt.Errorf("HTTP %d, unreadable reply", resp.StatusCode)
	}
	switch {
	case resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusUnprocessableEntity:
		return fmt.Errorf("%w (%s)", errNoRecord, env.MessageCode)
	case resp.StatusCode < 200 || resp.StatusCode > 299:
		return fmt.Errorf("HTTP %d %s: %s", resp.StatusCode, env.MessageCode, env.Message)
	}
	if out == nil || len(env.Data) == 0 || string(env.Data) == "null" {
		return nil
	}
	if err := json.Unmarshal(env.Data, out); err != nil {
		return fmt.Errorf("decoding reply: %w", err)
	}
	return nil
}

// parseDate reads the date formats Surepass uses.
func parseDate(s string) (time.Time, error) {
	s = strings.TrimSpace(s)
	for _, layout := range []string{time.DateOnly, "02-01-2006", "02/01/2006"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("unknown date %q", s)
}

// gender maps the Aadhaar's M/F/T.
func gender(s string) domain.Gender {
	switch strings.ToUpper(strings.TrimSpace(s)) {
	case "M", "MALE":
		return domain.GenderMale
	case "F", "FEMALE":
		return domain.GenderFemale
	case "T", "O", "TRANSGENDER", "OTHER":
		return domain.GenderOther
	}
	return ""
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}
