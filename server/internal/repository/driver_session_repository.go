package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// DriverSessionRepository persists driver-app auth sessions, mirroring
// [SessionRepository]. It is a separate table (not [SessionRepository]'s
// `sessions`) because that table's user_id FK targets `users`, not `drivers`.
// The rows share domain.Session's shape; UserID carries the driver's id.
type DriverSessionRepository struct {
	pool *pgxpool.Pool
}

// NewDriverSessionRepository wires the repository to a connection pool.
func NewDriverSessionRepository(pool *pgxpool.Pool) *DriverSessionRepository {
	return &DriverSessionRepository{pool: pool}
}

// Create inserts a session.
func (r *DriverSessionRepository) Create(ctx context.Context, s domain.Session) error {
	const q = `
		INSERT INTO driver_sessions (token, driver_id, created_at, expires_at)
		VALUES ($1, $2, $3, $4)`
	if _, err := r.pool.Exec(ctx, q, s.Token, s.UserID, s.CreatedAt, s.ExpiresAt); err != nil {
		return fmt.Errorf("creating driver session: %w", err)
	}
	return nil
}

// Delete removes a session by token (logout). Deleting an unknown token is a
// no-op, not an error.
func (r *DriverSessionRepository) Delete(ctx context.Context, token string) error {
	if _, err := r.pool.Exec(ctx, `DELETE FROM driver_sessions WHERE token = $1`, token); err != nil {
		return fmt.Errorf("deleting driver session: %w", err)
	}
	return nil
}

// ListActive returns every still-valid (unexpired) session. Used on boot to
// warm the in-memory cache from the durable store.
func (r *DriverSessionRepository) ListActive(ctx context.Context) ([]domain.Session, error) {
	const q = `
		SELECT token, driver_id, created_at, expires_at
		FROM driver_sessions
		WHERE expires_at > $1`

	rows, err := r.pool.Query(ctx, q, time.Now())
	if err != nil {
		return nil, fmt.Errorf("querying driver sessions: %w", err)
	}
	defer rows.Close()

	sessions := make([]domain.Session, 0)
	for rows.Next() {
		var s domain.Session
		if err := rows.Scan(&s.Token, &s.UserID, &s.CreatedAt, &s.ExpiresAt); err != nil {
			return nil, fmt.Errorf("scanning driver session: %w", err)
		}
		sessions = append(sessions, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating driver sessions: %w", err)
	}
	return sessions, nil
}
