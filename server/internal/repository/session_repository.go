package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// SessionRepository persists auth sessions. PostgreSQL is the durable source of
// truth; the service also mirrors live sessions into memstore for validation.
type SessionRepository struct {
	pool *pgxpool.Pool
}

// NewSessionRepository wires the repository to a connection pool.
func NewSessionRepository(pool *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{pool: pool}
}

// Create inserts a session.
func (r *SessionRepository) Create(ctx context.Context, s domain.Session) error {
	const q = `
		INSERT INTO sessions (token, user_id, created_at, expires_at)
		VALUES ($1, $2, $3, $4)`
	if _, err := r.pool.Exec(ctx, q, s.Token, s.UserID, s.CreatedAt, s.ExpiresAt); err != nil {
		return fmt.Errorf("creating session: %w", err)
	}
	return nil
}

// Delete removes a session by token (logout). Deleting an unknown token is a
// no-op, not an error.
func (r *SessionRepository) Delete(ctx context.Context, token string) error {
	if _, err := r.pool.Exec(ctx, `DELETE FROM sessions WHERE token = $1`, token); err != nil {
		return fmt.Errorf("deleting session: %w", err)
	}
	return nil
}

// ListActive returns every still-valid (unexpired) session. Used on boot to warm
// the in-memory cache from the durable store.
func (r *SessionRepository) ListActive(ctx context.Context) ([]domain.Session, error) {
	const q = `
		SELECT token, user_id, created_at, expires_at
		FROM sessions
		WHERE expires_at > $1`

	rows, err := r.pool.Query(ctx, q, time.Now())
	if err != nil {
		return nil, fmt.Errorf("querying sessions: %w", err)
	}
	defer rows.Close()

	sessions := make([]domain.Session, 0)
	for rows.Next() {
		var s domain.Session
		if err := rows.Scan(&s.Token, &s.UserID, &s.CreatedAt, &s.ExpiresAt); err != nil {
			return nil, fmt.Errorf("scanning session: %w", err)
		}
		sessions = append(sessions, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating sessions: %w", err)
	}
	return sessions, nil
}
