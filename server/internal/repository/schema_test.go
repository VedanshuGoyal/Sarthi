package repository

import (
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/sarthi/server/internal/domain"
)

// Money records outlive the accounts on them: deleting a customer or driver
// who has rides is refused (0018), rather than cascading through bookings
// and payment orders or orphaning rides still owed to a driver.
func TestSchema_DeletingAnAccountKeepsItsRides_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	user, driver := newTestUser(t, ctx, tx), newTestDriver(t, ctx, tx)
	booking := paidRide(t, ctx, tx, user, driver, time.Now(), 30000, 3900)
	orderForPaidRide(t, ctx, tx, domain.PaymentOrder{
		MerchantOrderID: "MOJUD_schema_test", BookingID: booking, UserID: user, AmountPaise: 30000,
		ProviderOrderID: "OMO1", ExpiresAt: time.Now().Add(time.Hour),
	})

	for _, del := range []struct{ what, sql, id string }{
		{"customer", `DELETE FROM users WHERE id = $1`, user},
		{"driver", `DELETE FROM drivers WHERE id = $1`, driver},
		{"booking", `DELETE FROM bookings WHERE id = $1`, booking},
	} {
		err := inSavepoint(t, ctx, tx, func(db DB) error {
			_, err := db.Exec(ctx, del.sql, del.id)
			return err
		})
		pgErr, ok := errors.AsType[*pgconn.PgError](err)
		if !ok || pgErr.Code != foreignKeyViolation {
			t.Errorf("deleting the %s: err = %v, want a foreign key violation", del.what, err)
		}
	}
	var rides int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM bookings WHERE id = $1 AND driver_id = $2`, booking, driver).
		Scan(&rides); err != nil || rides != 1 {
		t.Errorf("the ride is gone or lost its driver (%d, %v)", rides, err)
	}
}
