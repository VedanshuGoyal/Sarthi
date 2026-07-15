package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// recentPickupColumns is the shared SELECT list, in domain.RecentPickup order.
const recentPickupColumns = "place_id, address, lat, lng, used_at"

// RecentPickupRepository persists each customer's short pickup history.
type RecentPickupRepository struct {
	pool *pgxpool.Pool
}

// NewRecentPickupRepository wires the repository to a connection pool.
func NewRecentPickupRepository(pool *pgxpool.Pool) *RecentPickupRepository {
	return &RecentPickupRepository{pool: pool}
}

// ListByUser returns the user's most-recent pickups, newest first, up to limit.
func (r *RecentPickupRepository) ListByUser(ctx context.Context, userID string, limit int) ([]domain.RecentPickup, error) {
	const q = `
		SELECT ` + recentPickupColumns + `
		FROM recent_pickups
		WHERE user_id = $1
		ORDER BY used_at DESC
		LIMIT $2`

	rows, err := r.pool.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("querying recent pickups: %w", err)
	}
	return scanRecentPickups(rows) // owns closing rows
}

// Upsert records p as the user's newest pickup — bumping used_at when the same
// place is used again rather than duplicating it — prunes anything past limit,
// and returns the resulting list newest-first. The three statements run in one
// transaction so a concurrent read never sees a half-applied state.
func (r *RecentPickupRepository) Upsert(ctx context.Context, userID string, p domain.RecentPickup, limit int) ([]domain.RecentPickup, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("beginning tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op once committed

	const upsert = `
		INSERT INTO recent_pickups (user_id, place_id, address, lat, lng, used_at)
		VALUES ($1, $2, $3, $4, $5, now())
		ON CONFLICT (user_id, dedup_key)
		DO UPDATE SET address = EXCLUDED.address,
		              lat     = EXCLUDED.lat,
		              lng     = EXCLUDED.lng,
		              used_at = now()`
	if _, err := tx.Exec(ctx, upsert, userID, p.PlaceID, p.Address, p.Lat, p.Lng); err != nil {
		return nil, fmt.Errorf("upserting recent pickup: %w", err)
	}

	// Cap stored history at limit: drop everything but the newest rows.
	const prune = `
		DELETE FROM recent_pickups
		WHERE user_id = $1 AND dedup_key NOT IN (
			SELECT dedup_key FROM recent_pickups
			WHERE user_id = $1
			ORDER BY used_at DESC
			LIMIT $2
		)`
	if _, err := tx.Exec(ctx, prune, userID, limit); err != nil {
		return nil, fmt.Errorf("pruning recent pickups: %w", err)
	}

	const list = `
		SELECT ` + recentPickupColumns + `
		FROM recent_pickups
		WHERE user_id = $1
		ORDER BY used_at DESC
		LIMIT $2`
	rows, err := tx.Query(ctx, list, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("listing recent pickups: %w", err)
	}
	items, err := scanRecentPickups(rows)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("committing tx: %w", err)
	}
	return items, nil
}

// scanRecentPickups reads a result set into domain values and closes rows.
func scanRecentPickups(rows pgx.Rows) ([]domain.RecentPickup, error) {
	defer rows.Close()

	items := make([]domain.RecentPickup, 0)
	for rows.Next() {
		var p domain.RecentPickup
		if err := rows.Scan(&p.PlaceID, &p.Address, &p.Lat, &p.Lng, &p.UsedAt); err != nil {
			return nil, fmt.Errorf("scanning recent pickup: %w", err)
		}
		items = append(items, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating recent pickups: %w", err)
	}
	return items, nil
}
