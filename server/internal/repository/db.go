package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// DB is what a repository runs its statements on: a *pgxpool.Pool in the
// server, or a pgx.Tx in tests, which roll everything back. Begin on a
// pgx.Tx opens a savepoint, so a repository method that needs its own
// transaction works the same inside a test's.
type DB interface {
	Begin(ctx context.Context) (pgx.Tx, error)
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}
