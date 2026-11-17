package repository

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// allowAll lets an erasure go ahead whatever it finds, recording what it saw.
func allowAll(seen *domain.ErasureBlockers) func(domain.ErasureBlockers) error {
	return func(b domain.ErasureBlockers) error {
		*seen = b
		return nil
	}
}

// count runs a count(*) query that takes one argument.
func count(t *testing.T, ctx context.Context, db DB, q, arg string) int {
	t.Helper()
	var n int
	if err := db.QueryRow(ctx, q, arg).Scan(&n); err != nil {
		t.Fatalf("%s: %v", q, err)
	}
	return n
}

func insertRide(t *testing.T, ctx context.Context, db DB, userID string, driverID *string, status string) string {
	t.Helper()
	var id string
	if err := db.QueryRow(ctx, `
		INSERT INTO bookings (user_id, trip_type, details, status, driver_id, scheduled_at, fare_paise)
		VALUES ($1, 'roundTrip', '{}', $2, $3, now(), 24000) RETURNING id`,
		userID, status, driverID).Scan(&id); err != nil {
		t.Fatalf("inserting %s ride: %v", status, err)
	}
	return id
}

func TestErasureRepository_EraseUser_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewErasureRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	var phone string
	if err := tx.QueryRow(ctx, `SELECT phone_e164 FROM users WHERE id = $1`, user).Scan(&phone); err != nil {
		t.Fatal(err)
	}
	// Everything a customer leaves behind, and money records that must stay.
	paid := paidRide(t, ctx, tx, user, driver, time.Now(), 30000, 3900)
	if err := NewPaymentRepository(tx).InsertOrder(ctx, domain.PaymentOrder{
		MerchantOrderID: "MOJUD_erase_" + user, BookingID: paid, UserID: user, AmountPaise: 30000,
		ProviderOrderID: "OMO1", ExpiresAt: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	open := insertRide(t, ctx, tx, user, nil, "requested")
	for _, q := range []string{
		`INSERT INTO sessions (token, user_id, expires_at) VALUES ('erase-test-' || $1::text, $1::uuid, now() + interval '1 day')`,
		`INSERT INTO push_tokens (token, user_id) VALUES ('push-' || $1::text, $1::uuid)`,
		`INSERT INTO cars (user_id, registration, car_type, transmission) VALUES ($1, 'KA01AB1234', 'sedan', 'manual')`,
		`INSERT INTO recent_pickups (user_id, address, lat, lng) VALUES ($1, '12 MG Road', 12.97, 77.59)`,
	} {
		if _, err := tx.Exec(ctx, q, user); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}

	at := time.Date(2026, 11, 17, 22, 0, 0, 0, time.UTC)
	var seen domain.ErasureBlockers
	res, err := repo.EraseUser(ctx, user, at, allowAll(&seen))
	if err != nil {
		t.Fatalf("EraseUser: %v", err)
	}
	if seen != (domain.ErasureBlockers{}) || res.AlreadyErased || res.CancelledRequests != 1 {
		t.Errorf("blockers %+v, result %+v", seen, res)
	}

	var (
		name, email, newPhone string
		dob                   time.Time
		erasedAt              *time.Time
	)
	if err := tx.QueryRow(ctx, `SELECT name, email, phone_e164, date_of_birth, erased_at FROM users WHERE id = $1`, user).
		Scan(&name, &email, &newPhone, &dob, &erasedAt); err != nil {
		t.Fatal(err)
	}
	if name != domain.ErasedName || email != "deleted-"+user+"@deleted.invalid" || newPhone != "deleted-"+user ||
		dob.Year() != 1900 || erasedAt == nil || !erasedAt.Equal(at) {
		t.Errorf("after erasure: %q %q %q %v %v", name, email, newPhone, dob, erasedAt)
	}
	for _, q := range []string{
		`SELECT count(*) FROM sessions WHERE user_id = $1`,
		`SELECT count(*) FROM push_tokens WHERE user_id = $1`,
		`SELECT count(*) FROM cars WHERE user_id = $1`,
		`SELECT count(*) FROM recent_pickups WHERE user_id = $1`,
	} {
		if n := count(t, ctx, tx, q, user); n != 0 {
			t.Errorf("%s = %d after erasure", q, n)
		}
	}
	var status string
	if err := tx.QueryRow(ctx, `SELECT status FROM bookings WHERE id = $1`, open).Scan(&status); err != nil || status != "cancelled" {
		t.Errorf("open request is %q (%v), want cancelled", status, err)
	}
	// The paid ride and its order survive, still owed to the driver.
	if n := count(t, ctx, tx, `SELECT count(*) FROM bookings WHERE id = $1 AND paid_at IS NOT NULL AND payout_id IS NULL`, paid); n != 1 {
		t.Error("the paid ride is gone or changed")
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM payment_orders WHERE booking_id = $1`, paid); n != 1 {
		t.Error("the payment order is gone")
	}
	// The number is free to sign up again.
	if _, err := NewUserRepository(tx).CreateUser(ctx, CreateUserParams{
		PhoneE164: phone, Name: "Back Again", Email: "back@example.test", DateOfBirth: time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Errorf("re-registering the erased number: %v", err)
	}

	// Erasing again is harmless and says so.
	res, err = repo.EraseUser(ctx, user, at.Add(time.Hour), allowAll(&seen))
	if err != nil || !res.AlreadyErased {
		t.Errorf("second erasure: %+v, %v", res, err)
	}
	if err := tx.QueryRow(ctx, `SELECT erased_at FROM users WHERE id = $1`, user).Scan(&erasedAt); err != nil || !erasedAt.Equal(at) {
		t.Errorf("erased_at moved to %v (%v); the first erasure's time should stay", erasedAt, err)
	}
}

// What blocks erasure is read under lock and handed to allow; a refusal
// leaves every row as it was.
func TestErasureRepository_BlockersAndRefusal_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewErasureRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	insertRide(t, ctx, tx, user, &driver, "accepted")
	insertRide(t, ctx, tx, user, &driver, "completed") // fare, not paid
	insertRide(t, ctx, tx, user, nil, "requested")
	// Paid out, and settled by hand: neither blocks anyone.
	paidOut := paidRide(t, ctx, tx, user, driver, time.Now().Add(-time.Hour), 20000, 2600)
	if _, err := NewPaymentRepository(tx).RecordPayout(ctx, driver, "UTR-erasure-test",
		time.Now().Add(-time.Minute), time.Now(), ExpectedPayout{}); err != nil {
		t.Fatalf("RecordPayout: %v", err)
	}
	if payoutOf(t, ctx, tx, paidOut) == "" {
		t.Fatal("the payout did not cover the paid-out ride")
	}
	settled := paidRide(t, ctx, tx, user, driver, time.Now(), 10000, 0)
	if _, err := tx.Exec(ctx, `UPDATE bookings SET paid_mode = 'cash' WHERE id = $1`, settled); err != nil {
		t.Fatalf("settling by hand: %v", err)
	}
	// Paid: nothing for the customer, but the driver's share is still owed.
	paidRide(t, ctx, tx, user, driver, time.Now(), 30000, 3900)

	refused := errors.New("refused")
	for _, tc := range []struct {
		kind  string
		erase func(context.Context, string, time.Time, func(domain.ErasureBlockers) error) (domain.ErasureResult, error)
		id    string
		want  domain.ErasureBlockers
	}{
		{"customer", repo.EraseUser, user, domain.ErasureBlockers{ActiveRides: 1, UnpaidRides: 1}},
		{"driver", repo.EraseDriver, driver, domain.ErasureBlockers{ActiveRides: 1, UnpaidRides: 1, AwaitingPayout: 1}},
	} {
		var seen domain.ErasureBlockers
		_, err := tc.erase(ctx, tc.id, time.Now(), func(b domain.ErasureBlockers) error {
			seen = b
			return refused
		})
		if !errors.Is(err, refused) {
			t.Fatalf("%s: err = %v, want allow's error back", tc.kind, err)
		}
		if seen != tc.want {
			t.Errorf("%s: blockers %+v, want %+v", tc.kind, seen, tc.want)
		}
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM users WHERE id = $1 AND erased_at IS NULL AND name = 'Test Customer'`, user); n != 1 {
		t.Error("a refused erasure changed the customer")
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM bookings WHERE user_id = $1 AND status = 'requested'`, user); n != 1 {
		t.Error("a refused erasure cancelled the open request")
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM drivers WHERE id = $1 AND erased_at IS NULL`, driver); n != 1 {
		t.Error("a refused erasure changed the driver")
	}

	missing := "00000000-0000-0000-0000-000000000000"
	if _, err := repo.EraseUser(ctx, missing, time.Now(), allowAll(new(domain.ErasureBlockers))); !errors.Is(err, ErrAccountNotFound) {
		t.Errorf("unknown customer: err = %v, want ErrAccountNotFound", err)
	}
	if _, err := repo.EraseDriver(ctx, missing, time.Now(), allowAll(new(domain.ErasureBlockers))); !errors.Is(err, ErrAccountNotFound) {
		t.Errorf("unknown driver: err = %v, want ErrAccountNotFound", err)
	}
}

func TestErasureRepository_EraseDriver_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	repo := NewErasureRepository(tx)
	kyc := NewDriverKYCRepository(tx)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	tag := fmt.Sprint(time.Now().UnixNano())

	if err := kyc.SaveAadhaarVerification(ctx, driver, domain.AadhaarRecord{
		Name: "Test Driver", DateOfBirth: time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC), Last4: "0001",
	}, "fp-"+tag); err != nil {
		t.Fatalf("SaveAadhaarVerification: %v", err)
	}
	if err := kyc.SaveLicenseVerification(ctx, driver, domain.LicenseRecord{Number: "DL0420110012345"}); err != nil {
		t.Fatalf("SaveLicenseVerification: %v", err)
	}
	if _, err := kyc.UpsertBankAccount(ctx, driver, UpsertBankAccountParams{
		AccountHolderName: "Test Driver", AccountNumberEncrypted: []byte{1, 2, 3}, AccountNumberLast4: "1234", IFSCCode: "HDFC0001234",
	}); err != nil {
		t.Fatalf("UpsertBankAccount: %v", err)
	}
	for _, kind := range []string{"selfie", "aadhaar"} {
		if _, err := tx.Exec(ctx, `
			INSERT INTO driver_documents (driver_id, kind, object_key, content_type, byte_size, sha256)
			VALUES ($1::uuid, $2::text, 'drivers/' || $1::text || '/' || $2::text || '/x.jpg', 'image/jpeg', 10, 'abc')`, driver, kind); err != nil {
			t.Fatal(err)
		}
	}
	if err := kyc.RecordCheck(ctx, driver, domain.CheckDrivingLicense, "DL0420110012345", domain.CheckVerified, "Aadhaar ends 0001"); err != nil {
		t.Fatal(err)
	}
	for _, q := range []string{
		`INSERT INTO driver_sessions (token, driver_id, expires_at) VALUES ('erase-test-' || $1::text, $1::uuid, now() + interval '1 day')`,
		`INSERT INTO push_tokens (token, driver_id) VALUES ('push-' || $1::text, $1::uuid)`,
	} {
		if _, err := tx.Exec(ctx, q, driver); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	// A paid ride not yet paid out: the driver is owed this after erasure.
	paidRide(t, ctx, tx, user, driver, time.Now().Add(-time.Hour), 30000, 3900)

	res, err := repo.EraseDriver(ctx, driver, time.Now(), allowAll(new(domain.ErasureBlockers)))
	if err != nil {
		t.Fatalf("EraseDriver: %v", err)
	}
	if len(res.Documents) != 2 {
		t.Fatalf("documents to delete: %+v, want 2", res.Documents)
	}

	var (
		name, phone, status string
		last4, license      *string
		fingerprint, ident  *string
		aadhaarAt, erasedAt *time.Time
	)
	if err := tx.QueryRow(ctx, `
		SELECT name, phone_e164, kyc_status, aadhaar_last4, driving_license_number,
		       aadhaar_fingerprint, aadhaar_identity_fingerprint, aadhaar_verified_at, erased_at
		FROM drivers WHERE id = $1`, driver).
		Scan(&name, &phone, &status, &last4, &license, &fingerprint, &ident, &aadhaarAt, &erasedAt); err != nil {
		t.Fatal(err)
	}
	if name != domain.ErasedName || phone != "deleted-"+driver || status != "incomplete" ||
		last4 != nil || license != nil || fingerprint != nil || ident != nil || aadhaarAt != nil || erasedAt == nil {
		t.Errorf("after erasure: %q %q %q last4=%v licence=%v fp=%v ident=%v verified=%v erased=%v",
			name, phone, status, last4, license, fingerprint, ident, aadhaarAt, erasedAt)
	}
	for _, q := range []string{
		`SELECT count(*) FROM driver_bank_accounts WHERE driver_id = $1`,
		`SELECT count(*) FROM driver_sessions WHERE driver_id = $1`,
		`SELECT count(*) FROM push_tokens WHERE driver_id = $1`,
		`SELECT count(*) FROM driver_kyc_checks WHERE driver_id = $1 AND (provider_ref IS NOT NULL OR detail IS NOT NULL)`,
	} {
		if n := count(t, ctx, tx, q, driver); n != 0 {
			t.Errorf("%s = %d after erasure", q, n)
		}
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM driver_kyc_checks WHERE driver_id = $1`, driver); n != 1 {
		t.Error("the KYC check row went; it stays (scrubbed) for the cost audit")
	}

	// Money owed survives, on hold for want of a bank account.
	due, err := NewPaymentRepository(tx).DuePayouts(ctx, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	var owed int64
	for _, d := range due {
		if d.DriverID == driver {
			owed = d.AmountPaise
		}
	}
	if owed != 30000-3900 {
		t.Errorf("owed to the erased driver: %d, want %d", owed, 30000-3900)
	}

	// Images: listed for the sweep until each row is deleted.
	pending, err := repo.ErasedDriverDocuments(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	mine := 0
	for _, d := range pending {
		if d.DriverID == driver {
			mine++
		}
	}
	if mine != 2 {
		t.Errorf("sweep sees %d of the erased driver's images, want 2", mine)
	}
	for _, d := range res.Documents {
		if err := repo.DeleteDocument(ctx, d.ID); err != nil {
			t.Fatal(err)
		}
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM driver_documents WHERE driver_id = $1`, driver); n != 0 {
		t.Errorf("%d image rows left", n)
	}
}

// A driver a reviewer rejected can't erase their way back in with the same
// Aadhaar: the fingerprint stays.
func TestErasureRepository_RejectedDriverKeepsAadhaarFingerprint_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	kyc := NewDriverKYCRepository(tx)
	driver := newTestDriver(t, ctx, tx)
	fp := fmt.Sprint("fp-rejected-", time.Now().UnixNano())
	if err := kyc.SaveAadhaarVerification(ctx, driver, domain.AadhaarRecord{
		Name: "Test Driver", DateOfBirth: time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC), Last4: "0002",
	}, fp); err != nil {
		t.Fatal(err)
	}
	if err := kyc.ReviewKYC(ctx, driver, domain.KYCRejected, "Fake documents", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := NewErasureRepository(tx).EraseDriver(ctx, driver, time.Now(), allowAll(new(domain.ErasureBlockers))); err != nil {
		t.Fatal(err)
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM drivers WHERE aadhaar_identity_fingerprint = $1`, fp); n != 1 {
		t.Error("the rejected driver's Aadhaar fingerprint was cleared")
	}
	if n := count(t, ctx, tx, `SELECT count(*) FROM drivers WHERE id = $1 AND aadhaar_last4 IS NULL`, driver); n != 1 {
		t.Error("the rejected driver's Aadhaar digits were kept")
	}
}

func TestConsentIsRecordedAtSignUp_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	users, drivers := NewUserRepository(tx), NewDriverRepository(tx)
	stamp := time.Now().UnixNano() % 100_000_000
	dob := time.Date(1990, 1, 1, 0, 0, 0, 0, time.UTC)

	for i, version := range []string{"2026-11", ""} {
		u, err := users.CreateUser(ctx, CreateUserParams{
			PhoneE164: fmt.Sprintf("+9181%08d", stamp+int64(i)), Name: "Consent", Email: "c@example.test",
			DateOfBirth: dob, ConsentVersion: version,
		})
		if err != nil {
			t.Fatal(err)
		}
		d, err := drivers.CreateDriver(ctx, CreateDriverParams{
			PhoneE164: fmt.Sprintf("+9171%08d", stamp+int64(i)), Name: "Consent", ConsentVersion: version,
		})
		if err != nil {
			t.Fatal(err)
		}
		for _, row := range []struct{ table, id string }{{"users", u.ID}, {"drivers", d.ID}} {
			var (
				got *string
				at  *time.Time
			)
			if err := tx.QueryRow(ctx, `SELECT consent_version, consented_at FROM `+row.table+` WHERE id = $1`, row.id).
				Scan(&got, &at); err != nil {
				t.Fatal(err)
			}
			switch version {
			case "":
				if got != nil || at != nil {
					t.Errorf("%s with no consent sent: %v at %v, want NULLs", row.table, got, at)
				}
			default:
				if got == nil || *got != version || at == nil {
					t.Errorf("%s: consent %v at %v, want %q with a time", row.table, got, at, version)
				}
			}
		}
	}
}
