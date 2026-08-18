package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// ErrDriverPhoneTaken is returned when a driver account already exists for a
// phone number.
var ErrDriverPhoneTaken = errors.New("phone number already registered")

// ErrDriverNotFound is returned by lookups when no driver matches.
var ErrDriverNotFound = errors.New("driver not found")

// driverColumns is the shared SELECT list, in domain.Driver's persistent-field
// order (Status and Location are memstore-only and never read from here).
const driverColumns = "id, phone_e164, name, vehicle, created_at"

// DriverRepository reads and writes driver accounts.
type DriverRepository struct {
	pool *pgxpool.Pool
}

// NewDriverRepository wires the repository to a connection pool.
func NewDriverRepository(pool *pgxpool.Pool) *DriverRepository {
	return &DriverRepository{pool: pool}
}

// CreateDriverParams carries the fields needed to insert a new driver account.
type CreateDriverParams struct {
	PhoneE164 string
	Name      string
}

// CreateDriver inserts a new driver account and returns it with the
// DB-assigned id and timestamp. A duplicate phone number maps to
// [ErrDriverPhoneTaken].
func (r *DriverRepository) CreateDriver(ctx context.Context, p CreateDriverParams) (domain.Driver, error) {
	const q = `
		INSERT INTO drivers (phone_e164, name)
		VALUES ($1, $2)
		RETURNING ` + driverColumns

	var d domain.Driver
	err := r.pool.QueryRow(ctx, q, p.PhoneE164, p.Name).
		Scan(&d.ID, &d.PhoneE164, &d.Name, &d.Vehicle, &d.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
			return domain.Driver{}, ErrDriverPhoneTaken
		}
		return domain.Driver{}, fmt.Errorf("creating driver: %w", err)
	}
	return d, nil
}

// FindByPhone returns the driver account for a phone number, or
// [ErrDriverNotFound] if none exists. Used to log an already-registered
// number straight in.
func (r *DriverRepository) FindByPhone(ctx context.Context, phoneE164 string) (domain.Driver, error) {
	const q = `SELECT ` + driverColumns + ` FROM drivers WHERE phone_e164 = $1`
	return r.queryOne(ctx, q, phoneE164)
}

// FindByID returns the driver account with the given id, or [ErrDriverNotFound].
func (r *DriverRepository) FindByID(ctx context.Context, id string) (domain.Driver, error) {
	const q = `SELECT ` + driverColumns + ` FROM drivers WHERE id = $1`
	return r.queryOne(ctx, q, id)
}

// queryOne runs a single-row driver lookup, mapping "no rows" to
// [ErrDriverNotFound].
func (r *DriverRepository) queryOne(ctx context.Context, q string, args ...any) (domain.Driver, error) {
	var d domain.Driver
	err := r.pool.QueryRow(ctx, q, args...).
		Scan(&d.ID, &d.PhoneE164, &d.Name, &d.Vehicle, &d.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Driver{}, ErrDriverNotFound
	}
	if err != nil {
		return domain.Driver{}, fmt.Errorf("finding driver: %w", err)
	}
	return d, nil
}
