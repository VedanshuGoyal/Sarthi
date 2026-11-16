package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

type fakePayoutStore struct {
	due       []domain.PayoutDue
	recordErr error
	gotExpect *repository.ExpectedPayout
}

func (f *fakePayoutStore) DuePayouts(context.Context, time.Time) ([]domain.PayoutDue, error) {
	return f.due, nil
}

func (f *fakePayoutStore) RecordPayout(
	_ context.Context, driverID, reference string, _, at time.Time, expect repository.ExpectedPayout,
) (domain.DriverPayout, error) {
	f.gotExpect = &expect
	if f.recordErr != nil {
		return domain.DriverPayout{}, f.recordErr
	}
	return domain.DriverPayout{ID: "p1", DriverID: driverID, Reference: reference, Rides: 2, AmountPaise: 13050, CreatedAt: at}, nil
}

type plainOpener struct{}

func (plainOpener) Open(sealed []byte) ([]byte, error) { return sealed, nil }

func adminPayouts(store *fakePayoutStore) *AdminHandler {
	return NewAdminHandler(service.NewPayoutService(store, plainOpener{}), nil, nil, nil)
}

func postPayout(h *AdminHandler, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/admin/payouts", strings.NewReader(body))
	rec := httptest.NewRecorder()
	h.RecordPayout(rec, req)
	return rec
}

func TestRecordPayout_checksWhatTheListShowed(t *testing.T) {
	store := &fakePayoutStore{}
	rec := postPayout(adminPayouts(store),
		`{"driverId":"d1","reference":"UTR1","asOf":"2026-11-10T12:00:00Z","amountPaise":13050,"rides":2}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d, want 201: %s", rec.Code, rec.Body)
	}
	e := store.gotExpect
	if e == nil || e.AmountPaise == nil || *e.AmountPaise != 13050 || e.Rides == nil || *e.Rides != 2 {
		t.Errorf("expectation passed to the store = %+v, want 13050 paise / 2 rides", e)
	}
}

func TestRecordPayout_oldCallerWithoutTotals(t *testing.T) {
	store := &fakePayoutStore{}
	rec := postPayout(adminPayouts(store), `{"driverId":"d1","reference":"UTR1","asOf":"2026-11-10T12:00:00Z"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d, want 201: %s", rec.Code, rec.Body)
	}
	if e := store.gotExpect; e == nil || e.AmountPaise != nil || e.Rides != nil {
		t.Errorf("expectation = %+v, want none checked", e)
	}
}

func TestRecordPayout_staleListIsAConflict(t *testing.T) {
	store := &fakePayoutStore{recordErr: fmt.Errorf("%w (now 3 rides, 19140 paise)", repository.ErrPayoutMismatch)}
	rec := postPayout(adminPayouts(store), `{"driverId":"d1","reference":"UTR1","amountPaise":13050,"rides":2}`)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status %d, want 409: %s", rec.Code, rec.Body)
	}
	var body struct{ Code, Error string }
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body.Code != "payout_mismatch" {
		t.Errorf("body = %s, want code payout_mismatch", rec.Body)
	}
}
