package service

import (
	"strings"
	"testing"

	"github.com/sarthi/server/internal/domain"
)

// HUMAN REVIEW REQUIRED: KYC. With KYC_AUTO_CLEAR off — the launch default —
// a driver whose Aadhaar, licence and bank all agree still waits for a
// person, with nothing in the note for them to fix.
func TestSubmit_autoClearOffSendsEveryoneToAPerson(t *testing.T) {
	svc, store, _ := newTestService(t)
	svc.SetAutoClear(false)
	completeKYC(t, svc, store)

	kyc, err := svc.Submit(t.Context(), testDriverID)
	if err != nil {
		t.Fatalf("Submit: %v", err)
	}
	if kyc.Profile.KYCStatus != domain.KYCSubmitted {
		t.Errorf("status = %q, want %q", kyc.Profile.KYCStatus, domain.KYCSubmitted)
	}
	if kyc.Profile.KYCReviewNote != "" {
		t.Errorf("note = %q, want none: the checks agreed", kyc.Profile.KYCReviewNote)
	}
	if store.submittedAt == nil {
		t.Error("kycSubmittedAt was not recorded")
	}
}

// HUMAN REVIEW REQUIRED: KYC. A driver a reviewer already cleared who taps
// Submit again (or whose app retries) stays verified, note and all.
func TestSubmit_alreadyVerifiedStaysVerified(t *testing.T) {
	for _, autoClear := range []bool{false, true} {
		svc, store, _ := newTestService(t)
		svc.SetAutoClear(autoClear)
		completeKYC(t, svc, store)
		store.profile.KYCStatus = domain.KYCVerified
		store.profile.KYCReviewNote = "checked by hand"

		kyc, err := svc.Submit(t.Context(), testDriverID)
		if err != nil {
			t.Fatalf("autoClear=%v: Submit: %v", autoClear, err)
		}
		if kyc.Profile.KYCStatus != domain.KYCVerified || kyc.Profile.KYCReviewNote != "checked by hand" {
			t.Errorf("autoClear=%v: status %q, note %q; want verified and unchanged",
				autoClear, kyc.Profile.KYCStatus, kyc.Profile.KYCReviewNote)
		}
	}
}

// A mismatch still carries its reason for the reviewer, whatever the flag.
func TestSubmit_autoClearOffKeepsTheMismatchNote(t *testing.T) {
	svc, store, _ := newTestService(t)
	svc.SetAutoClear(false)
	completeKYC(t, svc, store)
	store.bankAccount.VerifiedName = "RAVI SHARMA"

	kyc, err := svc.Submit(t.Context(), testDriverID)
	if err != nil {
		t.Fatalf("Submit: %v", err)
	}
	if kyc.Profile.KYCStatus != domain.KYCSubmitted || !strings.Contains(kyc.Profile.KYCReviewNote, "RAVI SHARMA") {
		t.Errorf("status %q, note %q; want submitted naming the mismatch", kyc.Profile.KYCStatus, kyc.Profile.KYCReviewNote)
	}
}

// The default is off: a service nobody configured never clears a driver by
// itself.
func TestSubmit_autoClearDefaultsOff(t *testing.T) {
	svc, store, _ := newTestService(t)
	svc.autoClear = false // as NewDriverKYCService leaves it
	if fresh := NewDriverKYCService(nil, nil, nil, nil, nil, ""); fresh.autoClear {
		t.Fatal("NewDriverKYCService turned auto-clear on")
	}
	completeKYC(t, svc, store)
	if kyc, err := svc.Submit(t.Context(), testDriverID); err != nil || kyc.Profile.KYCStatus == domain.KYCVerified {
		t.Errorf("Submit = %q, %v; want not verified", kyc.Profile.KYCStatus, err)
	}

	// Incomplete is still incomplete either way.
	svc2, _, _ := newTestService(t)
	svc2.SetAutoClear(false)
	if _, err := svc2.Submit(t.Context(), testDriverID); err == nil {
		t.Error("an incomplete submission was accepted with auto-clear off")
	}
}
