package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/domain"
)

// carColumns is the shared SELECT list, in domain.Car order.
const carColumns = "id, registration, car_type, transmission, created_at"

// CarRepository persists each customer's saved cars.
type CarRepository struct {
	pool *pgxpool.Pool
}

// NewCarRepository wires the repository to a connection pool.
func NewCarRepository(pool *pgxpool.Pool) *CarRepository {
	return &CarRepository{pool: pool}
}

// ListByUser returns the user's saved cars, newest first.
func (r *CarRepository) ListByUser(ctx context.Context, userID string) ([]domain.Car, error) {
	const q = `
		SELECT ` + carColumns + `
		FROM cars
		WHERE user_id = $1
		ORDER BY created_at DESC`

	rows, err := r.pool.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("querying cars: %w", err)
	}
	return scanCars(rows) // owns closing rows
}

// Upsert saves c for the user and returns the stored row. Re-adding the same
// registration updates the car's type/transmission instead of duplicating it,
// so the write never conflicts and "add my car again" quietly corrects it.
func (r *CarRepository) Upsert(ctx context.Context, userID string, c domain.Car) (domain.Car, error) {
	const q = `
		INSERT INTO cars (user_id, registration, car_type, transmission)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, registration)
		DO UPDATE SET car_type     = EXCLUDED.car_type,
		              transmission = EXCLUDED.transmission
		RETURNING ` + carColumns

	var saved domain.Car
	err := r.pool.QueryRow(ctx, q, userID, c.Registration, c.CarType, c.Transmission).
		Scan(&saved.ID, &saved.Registration, &saved.CarType, &saved.Transmission, &saved.CreatedAt)
	if err != nil {
		return domain.Car{}, fmt.Errorf("upserting car: %w", err)
	}
	return saved, nil
}

// Delete removes the user's car with the given id, reporting whether a row
// was actually deleted. The id::text comparison keeps a malformed id from the
// client a plain "not found" instead of a UUID cast error.
func (r *CarRepository) Delete(ctx context.Context, userID, carID string) (bool, error) {
	const q = `DELETE FROM cars WHERE user_id = $1 AND id::text = $2`

	tag, err := r.pool.Exec(ctx, q, userID, carID)
	if err != nil {
		return false, fmt.Errorf("deleting car: %w", err)
	}
	return tag.RowsAffected() > 0, nil
}

// scanCars reads a result set into domain values and closes rows.
func scanCars(rows pgx.Rows) ([]domain.Car, error) {
	defer rows.Close()

	items := make([]domain.Car, 0)
	for rows.Next() {
		var c domain.Car
		if err := rows.Scan(&c.ID, &c.Registration, &c.CarType, &c.Transmission, &c.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning car: %w", err)
		}
		items = append(items, c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating cars: %w", err)
	}
	return items, nil
}
