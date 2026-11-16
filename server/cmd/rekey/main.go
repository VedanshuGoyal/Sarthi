// Command rekey re-seals the bank account numbers stored under one
// encryption key with another, so a real DOCUMENT_ENCRYPTION_KEY can replace
// the public development key without losing the numbers already stored.
//
//	DATABASE_URL=... DOCUMENT_ENCRYPTION_KEY=<new> rekey            # from the dev key
//	... OLD_DOCUMENT_ENCRYPTION_KEY=<old> rekey                     # from another key
//
// It runs in one transaction and is idempotent: rows that already open under
// the new key are left alone. Aadhaar fingerprints are HMACs of digits that are
// never stored, so they cannot be moved to a new pepper; the tool only reports
// how many exist.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/config"
	"github.com/sarthi/server/internal/secret"
)

func main() {
	if err := run(); err != nil {
		slog.Error("rekey failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		return errors.New("DATABASE_URL is required")
	}
	newKey, err := secret.ParseKey(os.Getenv("DOCUMENT_ENCRYPTION_KEY"))
	if err != nil {
		return fmt.Errorf("DOCUMENT_ENCRYPTION_KEY: %w", err)
	}
	oldKey := config.DevEncryptionKey()
	if v := os.Getenv("OLD_DOCUMENT_ENCRYPTION_KEY"); v != "" {
		if oldKey, err = secret.ParseKey(v); err != nil {
			return fmt.Errorf("OLD_DOCUMENT_ENCRYPTION_KEY: %w", err)
		}
	}
	oldC, err := secret.NewCipher(oldKey)
	if err != nil {
		return err
	}
	newC, err := secret.NewCipher(newKey)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after Commit

	rows, err := tx.Query(ctx, `SELECT driver_id, account_number_encrypted FROM driver_bank_accounts FOR UPDATE`)
	if err != nil {
		return err
	}
	type row struct {
		id     string
		sealed []byte
	}
	var all []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.sealed); err != nil {
			return err
		}
		all = append(all, r)
	}
	if err := rows.Err(); err != nil {
		return err
	}

	var moved, already int
	for _, r := range all {
		resealed, changed, err := reseal(oldC, newC, r.sealed)
		if err != nil {
			return fmt.Errorf("driver %s: %w", r.id, err)
		}
		if !changed {
			already++
			continue
		}
		if _, err := tx.Exec(ctx, `UPDATE driver_bank_accounts SET account_number_encrypted = $2 WHERE driver_id = $1`,
			r.id, resealed); err != nil {
			return err
		}
		moved++
	}
	var fingerprints int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM drivers WHERE aadhaar_fingerprint IS NOT NULL`).Scan(&fingerprints); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	slog.Info("rekey done", "resealed", moved, "already_on_new_key", already,
		"aadhaar_fingerprints_left_on_old_pepper", fingerprints)
	return nil
}

// reseal moves one sealed value from oldC to newC. A value that already opens
// under newC is returned unchanged (changed=false), which makes reruns safe.
func reseal(oldC, newC *secret.Cipher, sealed []byte) (out []byte, changed bool, err error) {
	if _, err := newC.Open(sealed); err == nil {
		return sealed, false, nil
	}
	plain, err := oldC.Open(sealed)
	if err != nil {
		return nil, false, fmt.Errorf("opens under neither key: %w", err)
	}
	out, err = newC.Seal(plain)
	return out, true, err
}
