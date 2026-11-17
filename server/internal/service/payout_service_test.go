package service

import (
	"context"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
)

type duePayoutStore struct{ due []domain.PayoutDue }

func (s duePayoutStore) DuePayouts(context.Context, time.Time) ([]domain.PayoutDue, error) {
	return s.due, nil
}

func (duePayoutStore) RecordPayout(
	context.Context, string, string, time.Time, time.Time, repository.ExpectedPayout,
) (domain.DriverPayout, error) {
	return domain.DriverPayout{}, nil
}

func (duePayoutStore) PayoutsForDriver(context.Context, string, int) ([]domain.DriverPayout, error) {
	return nil, nil
}

type reverseOpener struct{}

func (reverseOpener) Open(sealed []byte) ([]byte, error) {
	return []byte("number:" + string(sealed)), nil
}

func TestPayoutDue_onlyAConfirmedAccountOfAVerifiedDriverIsListed(t *testing.T) {
	confirmed := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	account := func(d domain.PayoutDue) domain.PayoutDue {
		d.AccountHolderName, d.IFSCCode, d.VerifiedName = "Asha Singh", "HDFC0001234", "ASHA SINGH"
		d.AccountNumberEncrypted, d.AccountUpdatedAt = []byte("1234"), &confirmed
		return d
	}
	store := duePayoutStore{due: []domain.PayoutDue{
		account(domain.PayoutDue{DriverID: "ok", KYCStatus: domain.KYCVerified, AccountVerifiedAt: &confirmed}),
		account(domain.PayoutDue{DriverID: "reopened", KYCStatus: domain.KYCIncomplete, AccountVerifiedAt: &confirmed}),
		account(domain.PayoutDue{DriverID: "unconfirmed", KYCStatus: domain.KYCVerified}),
		{DriverID: "no-account", KYCStatus: domain.KYCVerified},
	}}
	due, _, err := NewPayoutService(store, reverseOpener{}).Due(context.Background(), time.Time{})
	if err != nil {
		t.Fatalf("Due: %v", err)
	}
	byID := map[string]domain.PayoutDue{}
	for _, d := range due {
		byID[d.DriverID] = d
	}

	if ok := byID["ok"]; ok.OnHold || ok.AccountNumber != "number:1234" || ok.VerifiedName != "ASHA SINGH" {
		t.Errorf("verified driver = %+v, want listed with the number and the bank's name", ok)
	}
	for _, id := range []string{"reopened", "unconfirmed", "no-account"} {
		d := byID[id]
		if !d.OnHold || d.HoldReason == "" {
			t.Errorf("%s: onHold %v (%q), want held with a reason", id, d.OnHold, d.HoldReason)
		}
		if d.AccountNumber != "" || d.AccountHolderName != "" || d.IFSCCode != "" || d.VerifiedName != "" {
			t.Errorf("%s: bank details listed while on hold: %+v", id, d)
		}
	}
}
