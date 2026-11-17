package repository

import (
	"strings"
	"testing"
)

// /readyz passes on a migrated database and fails, naming what is missing,
// when the newest migrations were not applied — so redeploy.sh rolls back.
func TestSchemaReady_Integration(t *testing.T) {
	ctx, tx := rollbackTx(t)
	if err := SchemaReady(ctx, tx); err != nil {
		t.Fatalf("SchemaReady on a migrated DB: %v", err)
	}

	// Undo 0030, 0029 and 0028's drivers column inside the test's transaction.
	if _, err := tx.Exec(ctx, `DROP INDEX drivers_erased`); err != nil {
		t.Fatalf("dropping index: %v", err)
	}
	if _, err := tx.Exec(ctx, `ALTER TABLE drivers DROP COLUMN erased_at`); err != nil {
		t.Fatalf("dropping column: %v", err)
	}
	if _, err := tx.Exec(ctx, `ALTER TABLE bookings DROP COLUMN cancellation_fee_paise`); err != nil {
		t.Fatalf("dropping column: %v", err)
	}
	err := SchemaReady(ctx, tx)
	if err == nil {
		t.Fatal("SchemaReady passed on an un-migrated DB")
	}
	for _, want := range []string{"drivers.erased_at", "drivers_erased", "bookings.cancellation_fee_paise"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not name %s", err, want)
		}
	}
	if strings.Contains(err.Error(), "admin_actions") {
		t.Errorf("error %q names admin_actions, which is there", err)
	}
}
