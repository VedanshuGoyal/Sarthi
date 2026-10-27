package service

import (
	"bytes"
	"context"
	"errors"
	"image/jpeg"
	"io"
	"maps"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/secret"
	"github.com/sarthi/server/internal/storage"
)

const testDriverID = "driver-1"

func TestUploadDocumentStoresProcessedBytes(t *testing.T) {
	svc, store, blob := newTestService(t)

	raw := jpegWithEXIF(t, 300, 200)
	doc, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, raw)
	if err != nil {
		t.Fatalf("UploadDocument: %v", err)
	}

	if doc.Kind != domain.DocumentSelfie {
		t.Errorf("kind = %q, want %q", doc.Kind, domain.DocumentSelfie)
	}
	if doc.ContentType != DocumentContentType {
		t.Errorf("contentType = %q, want %q", doc.ContentType, DocumentContentType)
	}
	if doc.Status != domain.DocumentPending {
		t.Errorf("status = %q, want %q", doc.Status, domain.DocumentPending)
	}

	stored, ok := blob.objects[doc.ObjectKey]
	if !ok {
		t.Fatalf("nothing stored under %q; have %v", doc.ObjectKey, slices.Sorted(maps.Keys(blob.objects)))
	}
	// What lands in storage is the re-encoded image, not what was uploaded.
	if bytes.Equal(stored, raw) {
		t.Error("raw upload was stored verbatim; it should be re-encoded")
	}
	if bytes.Contains(stored, []byte("Exif\x00\x00")) {
		t.Error("stored object still carries EXIF")
	}
	if doc.ByteSize != int64(len(stored)) {
		t.Errorf("byteSize = %d, want %d", doc.ByteSize, len(stored))
	}
	// The key is scoped to the driver, so one driver's key can't name another's.
	if !strings.HasPrefix(doc.ObjectKey, "drivers/"+testDriverID+"/") {
		t.Errorf("object key %q is not scoped to the driver", doc.ObjectKey)
	}
	if store.profile.KYCStatus != domain.KYCIncomplete {
		t.Errorf("kycStatus = %q, want %q", store.profile.KYCStatus, domain.KYCIncomplete)
	}
}

// A retake must not leave the previous image paying for storage forever.
func TestUploadDocumentDeletesTheImageItReplaces(t *testing.T) {
	svc, _, blob := newTestService(t)

	first, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentAadhaar, encodeJPEG(t, 100, 100))
	if err != nil {
		t.Fatalf("first upload: %v", err)
	}
	second, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentAadhaar, encodeJPEG(t, 120, 120))
	if err != nil {
		t.Fatalf("retake: %v", err)
	}

	if first.ObjectKey == second.ObjectKey {
		t.Fatal("retake reused the object key; it should write a fresh object")
	}
	if _, ok := blob.objects[first.ObjectKey]; ok {
		t.Error("the replaced image is still in storage")
	}
	if _, ok := blob.objects[second.ObjectKey]; !ok {
		t.Error("the new image is missing from storage")
	}
}

// A selfie also gets the small copy customers see; the full image stays private.
func TestUploadSelfieStoresASmallDriverPhoto(t *testing.T) {
	svc, _, blob := newTestService(t)

	doc, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, encodeJPEG(t, 1200, 900))
	if err != nil {
		t.Fatalf("UploadDocument: %v", err)
	}
	stored, ok := blob.objects[driverPhotoKey(doc.ObjectKey)]
	if !ok {
		t.Fatalf("no driver photo stored; have %v", slices.Sorted(maps.Keys(blob.objects)))
	}
	cfg, err := jpeg.DecodeConfig(bytes.NewReader(stored))
	if err != nil {
		t.Fatalf("driver photo isn't a JPEG: %v", err)
	}
	if cfg.Width != DriverPhotoEdge || cfg.Height != 240 {
		t.Errorf("driver photo is %dx%d, want %dx240", cfg.Width, cfg.Height, DriverPhotoEdge)
	}

	photo, version, err := svc.OpenDriverPhoto(t.Context(), testDriverID)
	if err != nil {
		t.Fatalf("OpenDriverPhoto: %v", err)
	}
	if !bytes.Equal(photo, stored) {
		t.Error("OpenDriverPhoto returned something other than the stored copy")
	}
	if version != doc.SHA256[:12] {
		t.Errorf("version = %q, want %q", version, doc.SHA256[:12])
	}

	// Other documents never get a customer-facing copy.
	aadhaar, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentAadhaar, encodeJPEG(t, 100, 100))
	if err != nil {
		t.Fatalf("aadhaar upload: %v", err)
	}
	if _, ok := blob.objects[driverPhotoKey(aadhaar.ObjectKey)]; ok {
		t.Error("an Aadhaar upload produced a driver photo")
	}
}

func TestRetakingTheSelfieDeletesTheOldDriverPhoto(t *testing.T) {
	svc, _, blob := newTestService(t)

	first, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, encodeJPEG(t, 100, 100))
	if err != nil {
		t.Fatalf("first upload: %v", err)
	}
	second, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, encodeJPEG(t, 120, 120))
	if err != nil {
		t.Fatalf("retake: %v", err)
	}
	if _, ok := blob.objects[driverPhotoKey(first.ObjectKey)]; ok {
		t.Error("the replaced driver photo is still in storage")
	}
	if _, ok := blob.objects[driverPhotoKey(second.ObjectKey)]; !ok {
		t.Error("the new driver photo is missing")
	}
}

// Selfies uploaded before driver photos existed get one on first read.
func TestOpenDriverPhotoMakesOneForAnOlderSelfie(t *testing.T) {
	svc, _, blob := newTestService(t)

	doc, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, encodeJPEG(t, 640, 640))
	if err != nil {
		t.Fatalf("UploadDocument: %v", err)
	}
	delete(blob.objects, driverPhotoKey(doc.ObjectKey))

	photo, _, err := svc.OpenDriverPhoto(t.Context(), testDriverID)
	if err != nil {
		t.Fatalf("OpenDriverPhoto: %v", err)
	}
	if len(photo) == 0 {
		t.Fatal("OpenDriverPhoto returned no bytes")
	}
	if !bytes.Equal(blob.objects[driverPhotoKey(doc.ObjectKey)], photo) {
		t.Error("the photo made on read wasn't stored for next time")
	}
}

func TestOpenDriverPhotoWithoutASelfie(t *testing.T) {
	svc, _, _ := newTestService(t)
	if _, _, err := svc.OpenDriverPhoto(t.Context(), testDriverID); !errors.Is(err, ErrNoDriverPhoto) {
		t.Errorf("error = %v, want ErrNoDriverPhoto", err)
	}
}

// If the row can't be written, the bytes must not linger unreferenced.
func TestUploadDocumentRemovesObjectWhenTheRowFails(t *testing.T) {
	svc, store, blob := newTestService(t)
	store.upsertErr = errors.New("database is down")

	_, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, encodeJPEG(t, 100, 100))
	if err == nil {
		t.Fatal("UploadDocument succeeded, want an error")
	}
	if len(blob.objects) != 0 {
		t.Errorf("storage holds %d orphaned objects, want 0", len(blob.objects))
	}
}

func TestUploadDocumentRejectsUnknownKind(t *testing.T) {
	svc, _, blob := newTestService(t)

	_, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentKind("passport"), encodeJPEG(t, 50, 50))
	if !errors.Is(err, ErrUnknownDocumentKind) {
		t.Errorf("error = %v, want ErrUnknownDocumentKind", err)
	}
	if len(blob.objects) != 0 {
		t.Error("an unknown kind still wrote to storage")
	}
}

// The whole point of the Aadhaar handling: the number goes in, and nothing
// that could reconstruct it comes to rest.
func TestUpdateProfileNeverStoresTheAadhaarNumber(t *testing.T) {
	svc, store, _ := newTestService(t)
	const aadhaar = "123456789012"

	if err := svc.UpdateProfile(t.Context(), testDriverID, ProfileUpdate{
		AadhaarNumber: ptr(aadhaar),
	}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}

	got := store.lastProfileUpdate
	if got.AadhaarLast4 == nil || *got.AadhaarLast4 != "9012" {
		t.Errorf("aadhaarLast4 = %v, want 9012", got.AadhaarLast4)
	}
	if got.AadhaarFingerprint == nil || *got.AadhaarFingerprint == "" {
		t.Fatal("no Aadhaar fingerprint was stored")
	}
	if strings.Contains(*got.AadhaarFingerprint, aadhaar) {
		t.Error("the fingerprint contains the Aadhaar number")
	}
	// The fingerprint must be keyed, not a bare hash of the digits.
	if *got.AadhaarFingerprint == secret.Fingerprint(nil, aadhaar) {
		t.Error("the fingerprint is unpeppered and so is brute-forceable")
	}
}

func TestUpdateProfileNormalisesAndValidates(t *testing.T) {
	tests := map[string]struct {
		update  ProfileUpdate
		wantErr bool
		check   func(t *testing.T, got repository.UpdateProfileParams)
	}{
		"spaced Aadhaar is accepted": {
			update: ProfileUpdate{AadhaarNumber: ptr("1234 5678 9012")},
			check: func(t *testing.T, got repository.UpdateProfileParams) {
				if got.AadhaarLast4 == nil || *got.AadhaarLast4 != "9012" {
					t.Errorf("aadhaarLast4 = %v, want 9012", got.AadhaarLast4)
				}
			},
		},
		"short Aadhaar is rejected":     {update: ProfileUpdate{AadhaarNumber: ptr("12345")}, wantErr: true},
		"non-numeric Aadhaar rejected":  {update: ProfileUpdate{AadhaarNumber: ptr("abcdefghijkl")}, wantErr: true},
		"unknown transmission rejected": {update: ProfileUpdate{Transmission: ptr("tiptronic")}, wantErr: true},
		"unknown gender rejected":       {update: ProfileUpdate{Gender: ptr("unspecified")}, wantErr: true},
		"one-letter name rejected":      {update: ProfileUpdate{FullName: ptr("A")}, wantErr: true},
		"blank name rejected":           {update: ProfileUpdate{FullName: ptr("   ")}, wantErr: true},
		"short licence rejected":        {update: ProfileUpdate{DrivingLicenseNumber: ptr("DL1")}, wantErr: true},
		"gender is lowercased": {
			update: ProfileUpdate{Gender: ptr("Female")},
			check: func(t *testing.T, got repository.UpdateProfileParams) {
				if got.Gender == nil || *got.Gender != string(domain.GenderFemale) {
					t.Errorf("gender = %v, want female", got.Gender)
				}
			},
		},
		"licence is uppercased and stripped": {
			update: ProfileUpdate{DrivingLicenseNumber: ptr("dl-01 2019 0012345")},
			check: func(t *testing.T, got repository.UpdateProfileParams) {
				if got.DrivingLicenseNumber == nil || *got.DrivingLicenseNumber != "DL0120190012345" {
					t.Errorf("licence = %v, want DL0120190012345", got.DrivingLicenseNumber)
				}
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			svc, store, _ := newTestService(t)

			err := svc.UpdateProfile(t.Context(), testDriverID, tc.update)
			if tc.wantErr {
				if !errors.Is(err, ErrInvalidProfile) {
					t.Fatalf("error = %v, want ErrInvalidProfile", err)
				}
				if store.profileUpdates != 0 {
					t.Error("an invalid update still reached the store")
				}
				return
			}
			if err != nil {
				t.Fatalf("UpdateProfile: %v", err)
			}
			if tc.check != nil {
				tc.check(t, store.lastProfileUpdate)
			}
		})
	}
}

func TestUpdateProfileRejectsUnderageDriver(t *testing.T) {
	svc, _, _ := newTestService(t)
	// The fake clock is 2026-08-07; this driver turns 18 tomorrow.
	almost18 := time.Date(2008, time.August, 8, 0, 0, 0, 0, time.UTC)

	err := svc.UpdateProfile(t.Context(), testDriverID, ProfileUpdate{DateOfBirth: &almost18})
	if !errors.Is(err, ErrInvalidProfile) {
		t.Errorf("error = %v, want ErrInvalidProfile", err)
	}

	justTurned18 := time.Date(2008, time.August, 6, 0, 0, 0, 0, time.UTC)
	if err := svc.UpdateProfile(t.Context(), testDriverID, ProfileUpdate{DateOfBirth: &justTurned18}); err != nil {
		t.Errorf("UpdateProfile for an 18-year-old = %v, want nil", err)
	}
}

func TestSetBankAccountEncryptsTheNumber(t *testing.T) {
	svc, store, _ := newTestService(t)
	const accountNumber = "123456789012345"

	account, err := svc.SetBankAccount(t.Context(), testDriverID, "Asha Kumari", accountNumber, "hdfc0001234")
	if err != nil {
		t.Fatalf("SetBankAccount: %v", err)
	}

	if account.AccountNumberLast4 != "2345" {
		t.Errorf("last4 = %q, want 2345", account.AccountNumberLast4)
	}
	// IFSC is normalised, so a lowercase entry doesn't become a second bank.
	if account.IFSCCode != "HDFC0001234" {
		t.Errorf("ifsc = %q, want HDFC0001234", account.IFSCCode)
	}

	sealed := store.lastBankAccount.AccountNumberEncrypted
	if len(sealed) == 0 {
		t.Fatal("no encrypted account number was stored")
	}
	if bytes.Contains(sealed, []byte(accountNumber)) {
		t.Error("the stored ciphertext contains the account number in the clear")
	}
	// Payouts need it back, so encryption has to be reversible.
	opened, err := testCipher(t).Open(sealed)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if string(opened) != accountNumber {
		t.Errorf("decrypted = %q, want %q", opened, accountNumber)
	}
}

func TestSetBankAccountRejectsMalformedDetails(t *testing.T) {
	tests := map[string]struct{ holder, number, ifsc string }{
		"blank holder":     {"", "123456789", "HDFC0001234"},
		"short number":     {"Asha", "12345", "HDFC0001234"},
		"long number":      {"Asha", strings.Repeat("1", 19), "HDFC0001234"},
		"lettered number":  {"Asha", "12345678abc", "HDFC0001234"},
		"malformed IFSC":   {"Asha", "123456789", "HDFC1001234"},
		"short IFSC":       {"Asha", "123456789", "HDFC000"},
		"non-numeric IFSC": {"Asha", "123456789", "12340001234"},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			svc, store, _ := newTestService(t)

			_, err := svc.SetBankAccount(t.Context(), testDriverID, tc.holder, tc.number, tc.ifsc)
			if !errors.Is(err, ErrInvalidProfile) {
				t.Errorf("error = %v, want ErrInvalidProfile", err)
			}
			if store.lastBankAccount.AccountNumberEncrypted != nil {
				t.Error("invalid details were still stored")
			}
		})
	}
}

func TestSubmitRequiresEveryStep(t *testing.T) {
	svc, store, _ := newTestService(t)

	_, err := svc.Submit(t.Context(), testDriverID)
	if !errors.Is(err, ErrKYCIncomplete) {
		t.Fatalf("error = %v, want ErrKYCIncomplete", err)
	}
	// The message has to name what's outstanding, or the driver has nowhere
	// to go from the refusal.
	for _, want := range []string{
		"type of vehicle", "photo and name", "Aadhaar (verify with DigiLocker)",
		"driving licence", "bank details", "photo",
	} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not mention %q", err, want)
		}
	}
	if store.profile.KYCStatus == domain.KYCSubmitted {
		t.Error("an incomplete KYC was marked submitted")
	}
}

// When the Aadhaar, licence and bank all name the driver, they're cleared
// without anyone looking.
func TestSubmitClearsAMatchingDriver(t *testing.T) {
	svc, store, _ := newTestService(t)
	completeKYC(t, svc, store)

	kyc, err := svc.Submit(t.Context(), testDriverID)
	if err != nil {
		t.Fatalf("Submit: %v", err)
	}

	if kyc.Profile.KYCStatus != domain.KYCVerified {
		t.Errorf("status = %q, want %q (note %q)", kyc.Profile.KYCStatus, domain.KYCVerified, kyc.Profile.KYCReviewNote)
	}
	if store.submittedAt == nil {
		t.Error("kycSubmittedAt was not recorded")
	}
}

// A name that differs goes to a person, with the reason recorded.
func TestSubmitSendsAMismatchToReview(t *testing.T) {
	svc, store, _ := newTestService(t)
	completeKYC(t, svc, store)
	store.bankAccount.VerifiedName = "RAVI SHARMA"

	kyc, err := svc.Submit(t.Context(), testDriverID)
	if err != nil {
		t.Fatalf("Submit: %v", err)
	}
	if kyc.Profile.KYCStatus != domain.KYCSubmitted {
		t.Errorf("status = %q, want %q", kyc.Profile.KYCStatus, domain.KYCSubmitted)
	}
	if !strings.Contains(kyc.Profile.KYCReviewNote, "RAVI SHARMA") {
		t.Errorf("review note %q doesn't name the mismatch", kyc.Profile.KYCReviewNote)
	}
}

func TestDigiLockerVerifiesTheAadhaar(t *testing.T) {
	svc, store, _ := newTestService(t)
	verifier := svc.verifier.(*fakeVerifier)
	ctx := t.Context()

	if _, err := svc.StartDigiLocker(ctx, testDriverID); !errors.Is(err, ErrInvalidProfile) {
		t.Fatalf("start without an Aadhaar number: err = %v, want ErrInvalidProfile", err)
	}
	if err := svc.UpdateProfile(ctx, testDriverID, ProfileUpdate{AadhaarNumber: ptr("1234 5678 9012")}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}

	session, err := svc.StartDigiLocker(ctx, testDriverID)
	if err != nil {
		t.Fatalf("StartDigiLocker: %v", err)
	}
	if session.URL == "" || session.RedirectURL != testRedirect {
		t.Errorf("session = %+v", session)
	}

	verifier.state = domain.DigiLockerPending
	if _, err := svc.CompleteDigiLocker(ctx, testDriverID); !errors.Is(err, ErrVerificationPending) {
		t.Fatalf("complete while pending: err = %v, want ErrVerificationPending", err)
	}

	verifier.state = domain.DigiLockerCompleted
	kyc, err := svc.CompleteDigiLocker(ctx, testDriverID)
	if err != nil {
		t.Fatalf("CompleteDigiLocker: %v", err)
	}
	p := kyc.Profile
	if p.AadhaarVerifiedAt == nil || p.FullName != "Asha Kumari" || p.Gender != domain.GenderFemale {
		t.Errorf("profile after DigiLocker = %+v", p)
	}
	if store.profile.DigiLockerClientID != "" {
		t.Error("the used DigiLocker session was not cleared")
	}

	// The name is the Aadhaar's now; resending it is fine, changing it isn't.
	if err := svc.UpdateProfile(ctx, testDriverID, ProfileUpdate{FullName: ptr("Asha Kumari")}); err != nil {
		t.Errorf("resending the same name: %v", err)
	}
	if err := svc.UpdateProfile(ctx, testDriverID, ProfileUpdate{FullName: ptr("Someone Else")}); !errors.Is(err, ErrIdentityLocked) {
		t.Errorf("changing the name: err = %v, want ErrIdentityLocked", err)
	}
}

func TestDigiLockerRejectsAnotherAadhaar(t *testing.T) {
	svc, store, _ := newTestService(t)
	ctx := t.Context()
	if err := svc.UpdateProfile(ctx, testDriverID, ProfileUpdate{AadhaarNumber: ptr("123456781111")}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}
	if _, err := svc.StartDigiLocker(ctx, testDriverID); err != nil {
		t.Fatalf("StartDigiLocker: %v", err)
	}
	if _, err := svc.CompleteDigiLocker(ctx, testDriverID); !errors.Is(err, ErrAadhaarMismatch) {
		t.Fatalf("err = %v, want ErrAadhaarMismatch", err)
	}
	if store.profile.AadhaarVerifiedAt != nil {
		t.Error("a mismatched Aadhaar was marked verified")
	}
}

func TestVerifyDrivingLicense(t *testing.T) {
	cases := map[string]struct {
		rec     domain.LicenseRecord
		found   bool
		wantErr error
	}{
		"valid":     {rec: validLicense(), found: true},
		"not found": {found: false, wantErr: ErrLicenseNotFound},
		"expired": {rec: func() domain.LicenseRecord {
			r := validLicense()
			r.ValidUntil = time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC)
			return r
		}(), found: true, wantErr: ErrLicenseRejected},
		"two-wheels": {rec: func() domain.LicenseRecord { r := validLicense(); r.Classes = []string{"MCWG"}; return r }(), found: true, wantErr: ErrLicenseRejected},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			svc, store, _ := newTestService(t)
			verifier := svc.verifier.(*fakeVerifier)
			verifier.license, verifier.licenseFound = tc.rec, tc.found
			dob := time.Date(1995, time.March, 2, 0, 0, 0, 0, time.UTC)
			store.profile.DateOfBirth = &dob

			kyc, err := svc.VerifyDrivingLicense(t.Context(), testDriverID, "mp09 2019 0012345")
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("err = %v, want %v", err, tc.wantErr)
			}
			if tc.wantErr != nil {
				if store.profile.LicenseVerifiedAt != nil {
					t.Error("a refused licence was marked verified")
				}
				return
			}
			if verifier.licenseNumber != "MP0920190012345" {
				t.Errorf("looked up %q, want the normalised number", verifier.licenseNumber)
			}
			if kyc.Profile.LicenseVerifiedAt == nil || kyc.Profile.DrivingLicenseNumber != "MP0920190012345" {
				t.Errorf("profile = %+v", kyc.Profile)
			}
		})
	}
}

func TestChecksAreLimitedPerDay(t *testing.T) {
	svc, store, _ := newTestService(t)
	dob := time.Date(1995, time.March, 2, 0, 0, 0, 0, time.UTC)
	store.profile.DateOfBirth = &dob
	svc.verifier.(*fakeVerifier).licenseFound = false

	for i := range MaxChecksPerDay {
		if _, err := svc.VerifyDrivingLicense(t.Context(), testDriverID, "MP0920190012345"); !errors.Is(err, ErrLicenseNotFound) {
			t.Fatalf("attempt %d: err = %v", i+1, err)
		}
	}
	if _, err := svc.VerifyDrivingLicense(t.Context(), testDriverID, "MP0920190012345"); !errors.Is(err, ErrTooManyChecks) {
		t.Errorf("err = %v, want ErrTooManyChecks", err)
	}
}

func TestSetBankAccountRefusesAnAccountTheBankDoesntKnow(t *testing.T) {
	svc, store, _ := newTestService(t)
	svc.verifier.(*fakeVerifier).bank = domain.BankAccountRecord{}

	_, err := svc.SetBankAccount(t.Context(), testDriverID, "Asha Kumari", "123456789012", "HDFC0001234")
	if !errors.Is(err, ErrBankAccountInvalid) {
		t.Fatalf("err = %v, want ErrBankAccountInvalid", err)
	}
	if store.bankAccount != nil {
		t.Error("an unverified account was stored")
	}
}

func TestChecksNeedAVerifier(t *testing.T) {
	svc, _, _ := newTestService(t)
	svc.verifier = nil
	if _, err := svc.SetBankAccount(t.Context(), testDriverID, "Asha Kumari", "123456789012", "HDFC0001234"); !errors.Is(err, ErrVerificationUnavailable) {
		t.Errorf("bank: err = %v, want ErrVerificationUnavailable", err)
	}
	if _, err := svc.StartDigiLocker(t.Context(), testDriverID); !errors.Is(err, ErrVerificationUnavailable) {
		t.Errorf("digilocker: err = %v, want ErrVerificationUnavailable", err)
	}
}

// Changing a detail after submitting has to put the driver back in the queue,
// otherwise a verified record could be edited out from under the reviewer.
func TestEditingAfterSubmissionReopensReview(t *testing.T) {
	svc, store, _ := newTestService(t)
	completeKYC(t, svc, store)
	if _, err := svc.Submit(t.Context(), testDriverID); err != nil {
		t.Fatalf("Submit: %v", err)
	}

	if err := svc.UpdateProfile(t.Context(), testDriverID, ProfileUpdate{
		Transmission: ptr(string(domain.DriverTransmissionManual)),
	}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}

	if store.profile.KYCStatus != domain.KYCIncomplete {
		t.Errorf("status = %q, want %q after an edit", store.profile.KYCStatus, domain.KYCIncomplete)
	}
}

func TestOpenDocumentPrefersASignedURL(t *testing.T) {
	svc, _, blob := newTestService(t)
	if _, err := svc.UploadDocument(t.Context(), testDriverID, domain.DocumentSelfie, encodeJPEG(t, 80, 80)); err != nil {
		t.Fatalf("UploadDocument: %v", err)
	}

	// Local-style backend: no signing, so the caller gets a stream.
	url, body, err := svc.OpenDocument(t.Context(), testDriverID, domain.DocumentSelfie)
	if err != nil {
		t.Fatalf("OpenDocument: %v", err)
	}
	if url != "" {
		t.Errorf("url = %q, want empty for an unsigning backend", url)
	}
	if body == nil {
		t.Fatal("no body returned for an unsigning backend")
	}
	if err := body.Close(); err != nil {
		t.Fatalf("closing body: %v", err)
	}

	// S3-style backend: a signed URL, and the bytes never touch the server.
	blob.signedURL = "https://example.invalid/signed"
	url, body, err = svc.OpenDocument(t.Context(), testDriverID, domain.DocumentSelfie)
	if err != nil {
		t.Fatalf("OpenDocument: %v", err)
	}
	if url != blob.signedURL {
		t.Errorf("url = %q, want %q", url, blob.signedURL)
	}
	if body != nil {
		t.Error("a body was streamed even though a signed URL was available")
	}
}

func TestOpenDocumentReportsAMissingDocument(t *testing.T) {
	svc, _, _ := newTestService(t)

	if _, _, err := svc.OpenDocument(t.Context(), testDriverID, domain.DocumentSelfie); !errors.Is(err, repository.ErrDocumentNotFound) {
		t.Errorf("error = %v, want ErrDocumentNotFound", err)
	}
}

// --- helpers -------------------------------------------------------------

func ptr[T any](v T) *T { return &v }

func testCipher(t *testing.T) *secret.Cipher {
	t.Helper()
	c, err := secret.NewCipher(bytes.Repeat([]byte{0x11}, secret.KeyLength))
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}
	return c
}

func newTestService(t *testing.T) (*DriverKYCService, *fakeKYCStore, *fakeBlob) {
	t.Helper()
	store := newFakeKYCStore()
	blob := newFakeBlob()
	svc := NewDriverKYCService(store, blob, testCipher(t), []byte("test-pepper"), newFakeVerifier(), testRedirect)
	// Fixed clock so the age checks don't drift with the calendar.
	svc.now = func() time.Time {
		return time.Date(2026, time.August, 7, 12, 0, 0, 0, time.UTC)
	}
	return svc, store, blob
}

// completeKYC fills in and verifies every step, so a test can start from a
// driver who is ready to submit.
func completeKYC(t *testing.T, svc *DriverKYCService, store *fakeKYCStore) {
	t.Helper()
	ctx := t.Context()
	dob := time.Date(1995, time.March, 2, 0, 0, 0, 0, time.UTC)

	if err := svc.UpdateProfile(ctx, testDriverID, ProfileUpdate{
		Transmission:  ptr(string(domain.DriverTransmissionBoth)),
		FullName:      ptr("Asha Kumari"),
		DateOfBirth:   &dob,
		Gender:        ptr(string(domain.GenderFemale)),
		AadhaarNumber: ptr("123456789012"),
	}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}
	if _, err := svc.StartDigiLocker(ctx, testDriverID); err != nil {
		t.Fatalf("StartDigiLocker: %v", err)
	}
	if _, err := svc.CompleteDigiLocker(ctx, testDriverID); err != nil {
		t.Fatalf("CompleteDigiLocker: %v", err)
	}
	if _, err := svc.VerifyDrivingLicense(ctx, testDriverID, "MP0920190012345"); err != nil {
		t.Fatalf("VerifyDrivingLicense: %v", err)
	}
	if _, err := svc.SetBankAccount(ctx, testDriverID, "Asha Kumari", "123456789012", "HDFC0001234"); err != nil {
		t.Fatalf("SetBankAccount: %v", err)
	}
	if _, err := svc.UploadDocument(ctx, testDriverID, domain.DocumentSelfie, encodeJPEG(t, 100, 100)); err != nil {
		t.Fatalf("UploadDocument(selfie): %v", err)
	}
	if store.profile.KYCStatus != domain.KYCIncomplete {
		t.Fatalf("setup left status %q, want incomplete", store.profile.KYCStatus)
	}
}

// fakeBlob is an in-memory Blob. signedURL, when set, makes it behave like an
// S3 backend that can hand out pre-signed links.
type fakeBlob struct {
	objects   map[string][]byte
	signedURL string
	putErr    error
}

func newFakeBlob() *fakeBlob {
	return &fakeBlob{objects: map[string][]byte{}}
}

func (f *fakeBlob) Put(_ context.Context, key string, body []byte, _ string) error {
	if f.putErr != nil {
		return f.putErr
	}
	f.objects[key] = bytes.Clone(body)
	return nil
}

func (f *fakeBlob) Get(_ context.Context, key string) (io.ReadCloser, error) {
	body, ok := f.objects[key]
	if !ok {
		return nil, storage.ErrNotFound
	}
	return io.NopCloser(bytes.NewReader(body)), nil
}

func (f *fakeBlob) Delete(_ context.Context, key string) error {
	delete(f.objects, key)
	return nil
}

func (f *fakeBlob) SignedGetURL(context.Context, string, time.Duration) (string, error) {
	if f.signedURL == "" {
		return "", storage.ErrNoSignedURL
	}
	return f.signedURL, nil
}

// fakeKYCStore is an in-memory DriverKYCStore that records what it was asked
// to persist, so tests can assert on the values rather than on SQL.
type fakeKYCStore struct {
	documents map[domain.DocumentKind]domain.DriverDocument
	profile   domain.DriverProfile

	bankAccount     *domain.DriverBankAccount
	lastBankAccount repository.UpsertBankAccountParams

	lastProfileUpdate repository.UpdateProfileParams
	profileUpdates    int
	submittedAt       *time.Time

	checks []fakeCheck

	upsertErr error
	nextID    int
}

func newFakeKYCStore() *fakeKYCStore {
	return &fakeKYCStore{
		documents: map[domain.DocumentKind]domain.DriverDocument{},
		profile:   domain.DriverProfile{KYCStatus: domain.KYCIncomplete},
	}
}

func (f *fakeKYCStore) UpsertDocument(
	_ context.Context, _ string, p repository.UpsertDocumentParams,
) (domain.DriverDocument, string, error) {
	if f.upsertErr != nil {
		return domain.DriverDocument{}, "", f.upsertErr
	}

	var displaced string
	if existing, ok := f.documents[p.Kind]; ok && existing.ObjectKey != p.ObjectKey {
		displaced = existing.ObjectKey
	}

	f.nextID++
	doc := domain.DriverDocument{
		ID:          string(rune('a' + f.nextID)),
		Kind:        p.Kind,
		ObjectKey:   p.ObjectKey,
		ContentType: p.ContentType,
		ByteSize:    p.ByteSize,
		SHA256:      p.SHA256,
		Status:      domain.DocumentPending,
		UploadedAt:  time.Now(),
	}
	f.documents[p.Kind] = doc
	return doc, displaced, nil
}

func (f *fakeKYCStore) ListDocuments(context.Context, string) ([]domain.DriverDocument, error) {
	return slices.Collect(maps.Values(f.documents)), nil
}

func (f *fakeKYCStore) FindDocument(
	_ context.Context, _ string, kind domain.DocumentKind,
) (domain.DriverDocument, error) {
	doc, ok := f.documents[kind]
	if !ok {
		return domain.DriverDocument{}, repository.ErrDocumentNotFound
	}
	return doc, nil
}

func (f *fakeKYCStore) UpdateProfile(_ context.Context, _ string, p repository.UpdateProfileParams) error {
	f.lastProfileUpdate = p
	f.profileUpdates++

	// Mirror the repository's COALESCE semantics: nil leaves the value alone.
	if p.FullName != nil {
		f.profile.FullName = *p.FullName
	}
	if p.DateOfBirth != nil {
		f.profile.DateOfBirth = p.DateOfBirth
	}
	if p.Gender != nil {
		f.profile.Gender = domain.Gender(*p.Gender)
	}
	if p.Transmission != nil {
		f.profile.Transmission = domain.DriverTransmission(*p.Transmission)
	}
	if p.AadhaarLast4 != nil {
		f.profile.AadhaarLast4 = *p.AadhaarLast4
	}
	if p.DrivingLicenseNumber != nil {
		f.profile.DrivingLicenseNumber = *p.DrivingLicenseNumber
	}
	return nil
}

func (f *fakeKYCStore) FindProfile(context.Context, string) (domain.DriverProfile, error) {
	return f.profile, nil
}

func (f *fakeKYCStore) SetKYCStatus(
	_ context.Context, _ string, status domain.KYCStatus, recordSubmission bool,
) error {
	f.profile.KYCStatus = status
	// Mirrors the repository: the database stamps the time, once.
	if recordSubmission && f.submittedAt == nil {
		now := time.Now()
		f.submittedAt = &now
		f.profile.KYCSubmittedAt = &now
	}
	return nil
}

func (f *fakeKYCStore) UpsertBankAccount(
	_ context.Context, _ string, p repository.UpsertBankAccountParams,
) (domain.DriverBankAccount, error) {
	f.lastBankAccount = p
	account := domain.DriverBankAccount{
		AccountHolderName:  p.AccountHolderName,
		AccountNumberLast4: p.AccountNumberLast4,
		IFSCCode:           p.IFSCCode,
		UpdatedAt:          time.Now(),
		VerifiedName:       p.VerifiedName,
	}
	if p.Verified {
		now := time.Now()
		account.VerifiedAt = &now
	}
	f.bankAccount = &account
	return account, nil
}

func (f *fakeKYCStore) FindBankAccount(context.Context, string) (domain.DriverBankAccount, error) {
	if f.bankAccount == nil {
		return domain.DriverBankAccount{}, repository.ErrBankAccountNotFound
	}
	return *f.bankAccount, nil
}

func (f *fakeKYCStore) SetDigiLockerSession(_ context.Context, _ string, clientID string) error {
	f.profile.DigiLockerClientID = clientID
	return nil
}

func (f *fakeKYCStore) SaveAadhaarVerification(_ context.Context, _ string, rec domain.AadhaarRecord) error {
	now := time.Now()
	f.profile.FullName, f.profile.DateOfBirth = rec.Name, &rec.DateOfBirth
	if rec.Gender != "" {
		f.profile.Gender = rec.Gender
	}
	f.profile.AadhaarVerifiedAt = &now
	f.profile.DigiLockerClientID = ""
	f.profile.KYCStatus = domain.KYCIncomplete
	return nil
}

func (f *fakeKYCStore) SaveLicenseVerification(_ context.Context, _ string, rec domain.LicenseRecord) error {
	now := time.Now()
	f.profile.DrivingLicenseNumber = rec.Number
	f.profile.LicenseVerifiedAt = &now
	f.profile.LicenseName = rec.Name
	f.profile.LicenseValidUntil = nil
	if !rec.ValidUntil.IsZero() {
		f.profile.LicenseValidUntil = &domain.Date{Time: rec.ValidUntil}
	}
	f.profile.LicenseClasses = rec.Classes
	f.profile.KYCStatus = domain.KYCIncomplete
	return nil
}

func (f *fakeKYCStore) DecideKYC(_ context.Context, _ string, status domain.KYCStatus, note string) error {
	f.profile.KYCStatus, f.profile.KYCReviewNote = status, note
	if status != domain.KYCIncomplete && f.submittedAt == nil {
		now := time.Now()
		f.submittedAt, f.profile.KYCSubmittedAt = &now, &now
	}
	return nil
}

func (f *fakeKYCStore) RecordCheck(
	_ context.Context, _ string, kind domain.KYCCheckKind, _ string, outcome domain.KYCCheckOutcome, _ string,
) error {
	f.checks = append(f.checks, fakeCheck{kind, outcome})
	return nil
}

// CountChecks mirrors the repository's counting rules.
func (f *fakeKYCStore) CountChecks(_ context.Context, _ string, kind domain.KYCCheckKind, _ time.Time) (int, error) {
	n := 0
	for _, c := range f.checks {
		if c.kind != kind || c.outcome == domain.CheckPending || c.outcome == domain.CheckError {
			continue
		}
		if kind == domain.CheckDigiLocker && c.outcome != domain.CheckStarted {
			continue
		}
		n++
	}
	return n, nil
}

func (f *fakeKYCStore) ListKYCReviews(context.Context, domain.KYCStatus) ([]domain.KYCReview, error) {
	return nil, nil
}

type fakeCheck struct {
	kind    domain.KYCCheckKind
	outcome domain.KYCCheckOutcome
}

const testRedirect = "https://api.example/kyc/digilocker/done"

func validLicense() domain.LicenseRecord {
	return domain.LicenseRecord{
		Number:     "MP0920190012345",
		Name:       "ASHA KUMARI",
		ValidUntil: time.Date(2039, time.July, 23, 0, 0, 0, 0, time.UTC),
		Classes:    []string{"LMV", "MCWG"},
	}
}

// fakeVerifier answers like Surepass for a driver named Asha Kumari whose
// Aadhaar ends 9012.
type fakeVerifier struct {
	state         domain.DigiLockerState
	aadhaar       domain.AadhaarRecord
	license       domain.LicenseRecord
	licenseFound  bool
	licenseNumber string
	bank          domain.BankAccountRecord
}

func newFakeVerifier() *fakeVerifier {
	return &fakeVerifier{
		state: domain.DigiLockerCompleted,
		aadhaar: domain.AadhaarRecord{
			Name:        "Asha Kumari",
			DateOfBirth: time.Date(1995, time.March, 2, 0, 0, 0, 0, time.UTC),
			Gender:      domain.GenderFemale,
			Last4:       "9012",
		},
		license:      validLicense(),
		licenseFound: true,
		bank:         domain.BankAccountRecord{Exists: true, Name: "ASHA KUMARI"},
	}
}

func (f *fakeVerifier) StartDigiLocker(context.Context, string) (domain.DigiLockerSession, error) {
	return domain.DigiLockerSession{ClientID: "digilocker_test", URL: "https://digilocker.example/x"}, nil
}

func (f *fakeVerifier) DigiLockerStatus(context.Context, string) (domain.DigiLockerState, error) {
	return f.state, nil
}

func (f *fakeVerifier) DigiLockerAadhaar(context.Context, string) (domain.AadhaarRecord, error) {
	return f.aadhaar, nil
}

func (f *fakeVerifier) DrivingLicense(_ context.Context, number string, _ time.Time) (domain.LicenseRecord, bool, error) {
	f.licenseNumber = number
	return f.license, f.licenseFound, nil
}

func (f *fakeVerifier) BankAccount(context.Context, string, string) (domain.BankAccountRecord, error) {
	return f.bank, nil
}
