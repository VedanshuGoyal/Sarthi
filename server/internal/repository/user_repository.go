// Package repository persists domain entities to PostgreSQL. It is the only
// layer that knows SQL; services call it and receive clean domain types back.
package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// ErrPhoneTaken is returned when an account already exists for a phone number.
var ErrPhoneTaken = errors.New("phone number already registered")

// ErrUserNotFound is returned by lookups when no account matches.
var ErrUserNotFound = errors.New("user not found")

// userColumns is the shared SELECT list, in domain.User field order.
const userColumns = "id, phone_e164, name, email, date_of_birth, created_at"

// uniqueViolation is PostgreSQL's SQLSTATE for a unique-constraint violation.
const uniqueViolation = "23505"

// UserRepository reads and writes customer accounts.
type UserRepository struct {
	pool *pgxpool.Pool
}

// NewUserRepository wires the repository to a connection pool.
func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

// CreateUserParams carries the fields needed to insert a new account.
type CreateUserParams struct {
	PhoneE164   string
	Name        string
	Email       string
	DateOfBirth time.Time
}

// CreateUser inserts a new account and returns it with the DB-assigned id and
// timestamp. A duplicate phone number maps to [ErrPhoneTaken].
func (r *UserRepository) CreateUser(ctx context.Context, p CreateUserParams) (domain.User, error) {
	const q = `
		INSERT INTO users (phone_e164, name, email, date_of_birth)
		VALUES ($1, $2, $3, $4)
		RETURNING id, phone_e164, name, email, date_of_birth, created_at`

	var u domain.User
	err := r.pool.QueryRow(ctx, q, p.PhoneE164, p.Name, p.Email, p.DateOfBirth).
		Scan(&u.ID, &u.PhoneE164, &u.Name, &u.Email, &u.DateOfBirth, &u.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
			return domain.User{}, ErrPhoneTaken
		}
		return domain.User{}, fmt.Errorf("creating user: %w", err)
	}
	return u, nil
}

// FindByPhone returns the account for a phone number, or [ErrUserNotFound] if
// none exists. Used to log an already-registered number straight in.
func (r *UserRepository) FindByPhone(ctx context.Context, phoneE164 string) (domain.User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE phone_e164 = $1`
	return r.queryOne(ctx, q, phoneE164)
}

// FindByID returns the account with the given id, or [ErrUserNotFound].
func (r *UserRepository) FindByID(ctx context.Context, id string) (domain.User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE id = $1`
	return r.queryOne(ctx, q, id)
}

// queryOne runs a single-row user lookup, mapping "no rows" to [ErrUserNotFound].
func (r *UserRepository) queryOne(ctx context.Context, q string, args ...any) (domain.User, error) {
	var u domain.User
	err := r.pool.QueryRow(ctx, q, args...).
		Scan(&u.ID, &u.PhoneE164, &u.Name, &u.Email, &u.DateOfBirth, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, ErrUserNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("finding user: %w", err)
	}
	return u, nil
}

// ListUsers returns every account, newest first. Intended for admin/diagnostic
// use; production listing would paginate and be access-controlled.
func (r *UserRepository) ListUsers(ctx context.Context) ([]domain.User, error) {
	const q = `
		SELECT id, phone_e164, name, email, date_of_birth, created_at
		FROM users
		ORDER BY created_at DESC`

	rows, err := r.pool.Query(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("querying users: %w", err)
	}
	defer rows.Close()

	users := make([]domain.User, 0)
	for rows.Next() {
		var u domain.User
		if err := rows.Scan(
			&u.ID, &u.PhoneE164, &u.Name, &u.Email, &u.DateOfBirth, &u.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scanning user: %w", err)
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating users: %w", err)
	}
	return users, nil
}
