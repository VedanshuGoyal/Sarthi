package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/memstore"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/service"
)

// fakeEraser records each erasure asked for and answers with err.
type fakeEraser struct {
	calls []string
	err   error
}

func (f *fakeEraser) Erase(_ context.Context, kind domain.AccountKind, id string) (domain.ErasureReport, error) {
	f.calls = append(f.calls, string(kind)+":"+id)
	if f.err != nil {
		return domain.ErasureReport{}, f.err
	}
	return domain.ErasureReport{Kind: kind, ID: id, Status: "erased"}, nil
}

// memSessionRepo is a no-op durable store, so a real SessionService can
// issue tokens the router will accept.
type memSessionRepo struct{}

func (memSessionRepo) Create(context.Context, domain.Session) error         { return nil }
func (memSessionRepo) Delete(context.Context, string) error                 { return nil }
func (memSessionRepo) DeleteForUser(context.Context, string) error          { return nil }
func (memSessionRepo) ListActive(context.Context) ([]domain.Session, error) { return nil, nil }

type privacyRig struct {
	h                          http.Handler
	eraser                     *fakeEraser
	customerToken, driverToken string
}

func newPrivacyRig(t *testing.T, adminToken string) *privacyRig {
	t.Helper()
	users := service.NewSessionService(memSessionRepo{}, memstore.NewSessionCache())
	drivers := service.NewSessionService(memSessionRepo{}, memstore.NewSessionCache())
	cs, err := users.Issue(context.Background(), "customer-1")
	if err != nil {
		t.Fatal(err)
	}
	ds, err := drivers.Issue(context.Background(), "driver-1")
	if err != nil {
		t.Fatal(err)
	}
	e := &fakeEraser{}
	h := NewRouter(nil, users, nil, nil, nil, nil, drivers, nil, nil, nil, nil, nil, nil, nil, nil, nil, adminToken, nil, nil, e, AppPolicy{})
	return &privacyRig{h: h, eraser: e, customerToken: cs.Token, driverToken: ds.Token}
}

func (r *privacyRig) do(method, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	r.h.ServeHTTP(rec, req)
	return rec
}

func TestPrivacyRoutes_EachAppErasesOnlyItsOwnAccount(t *testing.T) {
	r := newPrivacyRig(t, "s3cret")

	rec := r.do(http.MethodDelete, "/me/account", r.customerToken)
	if rec.Code != http.StatusOK {
		t.Fatalf("DELETE /me/account: %d %s", rec.Code, rec.Body)
	}
	var report domain.ErasureReport
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil || report.Status != "erased" {
		t.Errorf("body %s (%v)", rec.Body, err)
	}
	if rec := r.do(http.MethodDelete, "/driver/account", r.driverToken); rec.Code != http.StatusOK {
		t.Fatalf("DELETE /driver/account: %d %s", rec.Code, rec.Body)
	}
	want := []string{"customer:customer-1", "driver:driver-1"}
	if len(r.eraser.calls) != 2 || r.eraser.calls[0] != want[0] || r.eraser.calls[1] != want[1] {
		t.Errorf("erased %v, want %v", r.eraser.calls, want)
	}

	// A token of one app is no good on the other's route, nor none at all.
	for _, tc := range []struct{ path, token string }{
		{"/me/account", r.driverToken},
		{"/driver/account", r.customerToken},
		{"/me/account", ""},
	} {
		if rec := r.do(http.MethodDelete, tc.path, tc.token); rec.Code != http.StatusUnauthorized {
			t.Errorf("DELETE %s with the wrong token: %d, want 401", tc.path, rec.Code)
		}
	}
	if len(r.eraser.calls) != 2 {
		t.Errorf("an unauthorised call reached the eraser: %v", r.eraser.calls)
	}
}

func TestPrivacyRoutes_AdminErasesByKindAndID(t *testing.T) {
	r := newPrivacyRig(t, "s3cret")
	const id = "11111111-1111-4111-8111-111111111111"

	if rec := r.do(http.MethodPost, "/admin/accounts/driver/"+id+"/erase", "wrong"); rec.Code != http.StatusUnauthorized {
		t.Errorf("wrong admin token: %d, want 401", rec.Code)
	}
	if rec := r.do(http.MethodPost, "/admin/accounts/driver/"+id+"/erase", r.driverToken); rec.Code != http.StatusUnauthorized {
		t.Errorf("a driver's own token on the admin route: %d, want 401", rec.Code)
	}
	for _, kind := range []string{"customer", "user", "driver"} {
		if rec := r.do(http.MethodPost, "/admin/accounts/"+kind+"/"+id+"/erase", "s3cret"); rec.Code != http.StatusOK {
			t.Errorf("admin erase %s: %d %s", kind, rec.Code, rec.Body)
		}
	}
	want := []string{"customer:" + id, "customer:" + id, "driver:" + id}
	if len(r.eraser.calls) != len(want) {
		t.Fatalf("erased %v, want %v", r.eraser.calls, want)
	}
	for i := range want {
		if r.eraser.calls[i] != want[i] {
			t.Errorf("call %d = %s, want %s", i, r.eraser.calls[i], want[i])
		}
	}
}

func TestPrivacyRoutes_ErrorStatuses(t *testing.T) {
	for _, tc := range []struct {
		err      error
		want     int
		wantCode string
	}{
		{&service.AccountBusyError{Reason: "Pay for your completed ride first."}, http.StatusConflict, "account_busy"},
		{repository.ErrAccountNotFound, http.StatusNotFound, ""},
		{service.ErrUnknownAccountKind, http.StatusBadRequest, ""},
		{errors.New("db down"), http.StatusInternalServerError, ""},
	} {
		r := newPrivacyRig(t, "s3cret")
		r.eraser.err = tc.err
		rec := r.do(http.MethodDelete, "/me/account", r.customerToken)
		if rec.Code != tc.want {
			t.Errorf("%v: status %d, want %d", tc.err, rec.Code, tc.want)
		}
		var body errorResponse
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if body.Code != tc.wantCode {
			t.Errorf("%v: code %q, want %q", tc.err, body.Code, tc.wantCode)
		}
		if tc.want == http.StatusConflict && body.Error != tc.err.Error() {
			t.Errorf("409 body says %q, want the reason for the person", body.Error)
		}
	}
}
