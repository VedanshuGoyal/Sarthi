package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PushTokenRepository stores the FCM registration tokens of customer and
// driver app installs. A token belongs to one account at a time: saving it
// for another account (a different sign-in on the same phone) moves it.
type PushTokenRepository struct {
	pool *pgxpool.Pool
}

// NewPushTokenRepository wires the repository to a connection pool.
func NewPushTokenRepository(pool *pgxpool.Pool) *PushTokenRepository {
	return &PushTokenRepository{pool: pool}
}

// SaveForUser registers token as userID's customer-app install.
func (r *PushTokenRepository) SaveForUser(ctx context.Context, userID, token string) error {
	const q = `
		INSERT INTO push_tokens (token, user_id) VALUES ($1, $2)
		ON CONFLICT (token) DO UPDATE
		SET user_id = EXCLUDED.user_id, driver_id = NULL, updated_at = now()`
	if _, err := r.pool.Exec(ctx, q, token, userID); err != nil {
		return fmt.Errorf("saving user push token: %w", err)
	}
	return nil
}

// SaveForDriver registers token as driverID's driver-app install.
func (r *PushTokenRepository) SaveForDriver(ctx context.Context, driverID, token string) error {
	const q = `
		INSERT INTO push_tokens (token, driver_id) VALUES ($1, $2)
		ON CONFLICT (token) DO UPDATE
		SET driver_id = EXCLUDED.driver_id, user_id = NULL, updated_at = now()`
	if _, err := r.pool.Exec(ctx, q, token, driverID); err != nil {
		return fmt.Errorf("saving driver push token: %w", err)
	}
	return nil
}

// DeleteForUser forgets token if it is userID's (sign-out). Unknown tokens
// are a no-op.
func (r *PushTokenRepository) DeleteForUser(ctx context.Context, userID, token string) error {
	if _, err := r.pool.Exec(ctx, `DELETE FROM push_tokens WHERE token = $1 AND user_id = $2`, token, userID); err != nil {
		return fmt.Errorf("deleting user push token: %w", err)
	}
	return nil
}

// DeleteForDriver forgets token if it is driverID's (sign-out).
func (r *PushTokenRepository) DeleteForDriver(ctx context.Context, driverID, token string) error {
	if _, err := r.pool.Exec(ctx, `DELETE FROM push_tokens WHERE token = $1 AND driver_id = $2`, token, driverID); err != nil {
		return fmt.Errorf("deleting driver push token: %w", err)
	}
	return nil
}

// Delete forgets token whoever holds it — FCM reported it unregistered.
func (r *PushTokenRepository) Delete(ctx context.Context, token string) error {
	if _, err := r.pool.Exec(ctx, `DELETE FROM push_tokens WHERE token = $1`, token); err != nil {
		return fmt.Errorf("deleting push token: %w", err)
	}
	return nil
}

// ForUser lists userID's install tokens.
func (r *PushTokenRepository) ForUser(ctx context.Context, userID string) ([]string, error) {
	rows, err := r.pool.Query(ctx, `SELECT token FROM push_tokens WHERE user_id = $1`, userID)
	if err != nil {
		return nil, fmt.Errorf("listing user push tokens: %w", err)
	}
	return collectTokens(rows)
}

// ForDrivers returns the install tokens of every driver in driverIDs, keyed
// by driver. Drivers with no token are absent.
func (r *PushTokenRepository) ForDrivers(ctx context.Context, driverIDs []string) (map[string][]string, error) {
	out := map[string][]string{}
	if len(driverIDs) == 0 {
		return out, nil
	}
	rows, err := r.pool.Query(ctx,
		`SELECT driver_id::text, token FROM push_tokens WHERE driver_id = ANY($1::uuid[])`, driverIDs)
	if err != nil {
		return nil, fmt.Errorf("listing driver push tokens: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var driverID, token string
		if err := rows.Scan(&driverID, &token); err != nil {
			return nil, fmt.Errorf("reading driver push tokens: %w", err)
		}
		out[driverID] = append(out[driverID], token)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("reading driver push tokens: %w", err)
	}
	return out, nil
}

func collectTokens(rows pgx.Rows) ([]string, error) {
	tokens, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("reading push tokens: %w", err)
	}
	return tokens, nil
}
