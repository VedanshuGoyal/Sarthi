package repository

import (
	"context"
	"fmt"
	"strings"
)

// SchemaReady reports whether the database holds the newest objects this
// binary needs, so /readyz fails — and redeploy.sh rolls back — when a new
// build is started before its migrations were applied. It is one catalogue
// lookup, cheap enough for every readiness probe, and it reaches Postgres,
// so it also covers what a ping would. Bump the probes when a migration
// adds something the server can't run without.
func SchemaReady(ctx context.Context, db DB) error {
	var adminActions, erasedAt, erasedIndex bool
	err := db.QueryRow(ctx, `
		SELECT to_regclass('admin_actions') IS NOT NULL,
		       EXISTS (SELECT 1 FROM pg_attribute
		               WHERE attrelid = to_regclass('drivers')
		                 AND attname = 'erased_at' AND NOT attisdropped),
		       to_regclass('drivers_erased') IS NOT NULL`).
		Scan(&adminActions, &erasedAt, &erasedIndex)
	if err != nil {
		return fmt.Errorf("checking schema: %w", err)
	}
	var missing []string
	if !adminActions {
		missing = append(missing, "table admin_actions (0026)")
	}
	if !erasedAt {
		missing = append(missing, "column drivers.erased_at (0028)")
	}
	if !erasedIndex {
		missing = append(missing, "index drivers_erased (0029)")
	}
	if len(missing) > 0 {
		return fmt.Errorf("schema is behind this build; apply migrations first: missing %s",
			strings.Join(missing, ", "))
	}
	return nil
}
