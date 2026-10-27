package surepass

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

var fixedNow = time.Date(2026, time.October, 27, 10, 0, 0, 0, time.UTC)

// fakeSurepass answers each path with a canned status and body, and records
// what it was sent.
type fakeSurepass struct {
	replies map[string]reply
	bodies  map[string]map[string]any
	auth    string
}

type reply struct {
	status int
	body   string
}

func newFake(t *testing.T, replies map[string]reply) (*fakeSurepass, *Client) {
	t.Helper()
	f := &fakeSurepass{replies: replies, bodies: map[string]map[string]any{}}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.auth = r.Header.Get("Authorization")
		if r.Body != nil {
			raw, _ := io.ReadAll(r.Body)
			var body map[string]any
			if json.Unmarshal(raw, &body) == nil {
				f.bodies[r.URL.Path] = body
			}
		}
		rep, ok := f.replies[r.Method+" "+r.URL.Path]
		if !ok {
			t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(rep.status)
		io.WriteString(w, rep.body)
	}))
	t.Cleanup(srv.Close)
	return f, New(srv.URL, "test-token", WithClock(func() time.Time { return fixedNow }))
}

func TestStartDigiLocker(t *testing.T) {
	f, c := newFake(t, map[string]reply{
		"POST /api/v1/digilocker/initialize": {200, `{"data":{"client_id":"digilocker_abc","token":"x","url":"https://digilocker-sdk.notbot.in/?token=x","expiry_seconds":600.0},"status_code":200,"success":true}`},
	})
	s, err := c.StartDigiLocker(t.Context(), "https://api.example/kyc/digilocker/done")
	if err != nil {
		t.Fatalf("StartDigiLocker: %v", err)
	}
	if s.ClientID != "digilocker_abc" || s.URL == "" {
		t.Errorf("session = %+v", s)
	}
	if want := fixedNow.Add(10 * time.Minute); !s.ExpiresAt.Equal(want) {
		t.Errorf("expiresAt = %v, want %v", s.ExpiresAt, want)
	}
	if f.auth != "Bearer test-token" {
		t.Errorf("Authorization = %q", f.auth)
	}
	data := f.bodies["/api/v1/digilocker/initialize"]["data"].(map[string]any)
	if data["redirect_url"] != "https://api.example/kyc/digilocker/done" || data["signup_flow"] != true {
		t.Errorf("initialize body = %v", data)
	}
}

func TestDigiLockerStatus(t *testing.T) {
	cases := map[string]struct {
		rep  reply
		want domain.DigiLockerState
	}{
		"completed": {reply{200, `{"data":{"status":"completed","completed":true,"failed":false},"success":true}`}, domain.DigiLockerCompleted},
		"pending":   {reply{200, `{"data":{"status":"pending","completed":false,"failed":false},"success":true}`}, domain.DigiLockerPending},
		"failed":    {reply{200, `{"data":{"status":"failed","completed":false,"failed":true},"success":true}`}, domain.DigiLockerFailed},
		"unknown":   {reply{404, `{"data":null,"status_code":404,"success":false,"message_code":"client_not_found"}`}, domain.DigiLockerFailed},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			_, c := newFake(t, map[string]reply{"GET /api/v1/digilocker/status/digilocker_abc": tc.rep})
			got, err := c.DigiLockerStatus(t.Context(), "digilocker_abc")
			if err != nil {
				t.Fatalf("DigiLockerStatus: %v", err)
			}
			if got != tc.want {
				t.Errorf("state = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestDigiLockerStatusServerError(t *testing.T) {
	_, c := newFake(t, map[string]reply{
		"GET /api/v1/digilocker/status/x": {500, `{"status_code":500,"success":false,"message_code":"internal_error"}`},
	})
	if _, err := c.DigiLockerStatus(t.Context(), "x"); err == nil {
		t.Error("a 500 was not reported as an error")
	}
}

func TestDigiLockerAadhaar(t *testing.T) {
	_, c := newFake(t, map[string]reply{
		"GET /api/v1/digilocker/download-aadhaar/digilocker_abc": {200, `{"data":{"client_id":"digilocker_abc",
			"digilocker_metadata":{"name":"ASHA KUMARI","gender":"F","dob":"1995-03-02"},
			"aadhaar_xml_data":{"full_name":"Asha Kumari","dob":"02-03-1995","gender":"F","masked_aadhaar":"XXXXXXXX9012","profile_image":"..."}},
			"success":true}`},
	})
	rec, err := c.DigiLockerAadhaar(t.Context(), "digilocker_abc")
	if err != nil {
		t.Fatalf("DigiLockerAadhaar: %v", err)
	}
	want := domain.AadhaarRecord{
		Name:        "Asha Kumari",
		DateOfBirth: time.Date(1995, time.March, 2, 0, 0, 0, 0, time.UTC),
		Gender:      domain.GenderFemale,
		Last4:       "9012",
	}
	if rec != want {
		t.Errorf("record = %+v, want %+v", rec, want)
	}
}

func TestDrivingLicense(t *testing.T) {
	f, c := newFake(t, map[string]reply{
		"POST /api/v1/driving-license/driving-license": {200, `{"data":{"license_number":"MP0920190012345","name":"ASHA KUMARI",
			"doe":"2039-07-23","transport_doe":"1800-01-01","vehicle_classes":["LMV","MCWG"]},"success":true}`},
	})
	dob := time.Date(1995, time.March, 2, 0, 0, 0, 0, time.UTC)
	rec, found, err := c.DrivingLicense(t.Context(), "MP0920190012345", dob)
	if err != nil || !found {
		t.Fatalf("DrivingLicense: found=%v err=%v", found, err)
	}
	if rec.Name != "ASHA KUMARI" || !slices.Equal(rec.Classes, []string{"LMV", "MCWG"}) {
		t.Errorf("record = %+v", rec)
	}
	if want := time.Date(2039, time.July, 23, 0, 0, 0, 0, time.UTC); !rec.ValidUntil.Equal(want) {
		t.Errorf("validUntil = %v, want %v", rec.ValidUntil, want)
	}
	if got := f.bodies["/api/v1/driving-license/driving-license"]["dob"]; got != "1995-03-02" {
		t.Errorf("dob sent = %v", got)
	}
}

func TestDrivingLicenseNotFound(t *testing.T) {
	_, c := newFake(t, map[string]reply{
		"POST /api/v1/driving-license/driving-license": {422, `{"data":{},"status_code":422,"success":false,"message":"Verification Failed.","message_code":"verification_failed"}`},
	})
	_, found, err := c.DrivingLicense(t.Context(), "MP0920190012345", fixedNow)
	if err != nil || found {
		t.Errorf("found=%v err=%v, want not found and no error", found, err)
	}
}

func TestBankAccount(t *testing.T) {
	cases := map[string]struct {
		rep  reply
		want domain.BankAccountRecord
	}{
		"exists":  {reply{200, `{"data":{"account_exists":true,"full_name":"ASHA KUMARI ","status":"success"},"success":true}`}, domain.BankAccountRecord{Exists: true, Name: "ASHA KUMARI"}},
		"no such": {reply{200, `{"data":{"account_exists":false,"full_name":null},"success":true}`}, domain.BankAccountRecord{}},
		"refused": {reply{422, `{"data":{"account_exists":false},"status_code":422,"success":false,"message_code":"verification_failed"}`}, domain.BankAccountRecord{}},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			_, c := newFake(t, map[string]reply{"POST /api/v1/bank-verification": tc.rep})
			got, err := c.BankAccount(t.Context(), "123456789012", "HDFC0001234")
			if err != nil {
				t.Fatalf("BankAccount: %v", err)
			}
			if got != tc.want {
				t.Errorf("record = %+v, want %+v", got, tc.want)
			}
		})
	}
}
