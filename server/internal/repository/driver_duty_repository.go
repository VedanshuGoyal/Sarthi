package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// dutyWriteEvery is how often a heartbeat from an on-duty driver is
// written: the app reports every 20 s, and a minute is plenty to rebuild
// presence from and to notice a silent app.
const dutyWriteEvery = time.Minute

// DriverDutyRepository keeps drivers' on/off duty and last position on
// their row (see migration 0022).
type DriverDutyRepository struct {
	db DB
}

// NewDriverDutyRepository wires the repository to a pool (or a transaction).
func NewDriverDutyRepository(db DB) *DriverDutyRepository {
	return &DriverDutyRepository{db: db}
}

// SaveDuty records that driverID's app reported in on duty at at, from
// lat/lng when given (both or neither). Going on duty is always written; a
// heartbeat at most every dutyWriteEvery.
func (r *DriverDutyRepository) SaveDuty(ctx context.Context, driverID string, at time.Time, lat, lng *float64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE drivers
		SET on_duty_at = coalesce(on_duty_at, $2),
		    last_seen_at = $2,
		    last_lat = coalesce($3, last_lat),
		    last_lng = coalesce($4, last_lng)
		WHERE id = $1
		  AND (on_duty_at IS NULL OR last_seen_at IS NULL OR last_seen_at <= $5)`,
		driverID, at, lat, lng, at.Add(-dutyWriteEvery))
	if err != nil {
		return rideErr(err, ErrDriverNotFound, "saving duty")
	}
	return nil
}

// EndDuty takes driverID off duty. Their last position and sighting stay.
func (r *DriverDutyRepository) EndDuty(ctx context.Context, driverID string) error {
	if _, err := r.db.Exec(ctx, `UPDATE drivers SET on_duty_at = NULL WHERE id = $1`, driverID); err != nil {
		return rideErr(err, ErrDriverNotFound, "ending duty")
	}
	return nil
}

// OnDuty lists the drivers on duty whose app reported in at or after
// seenSince.
func (r *DriverDutyRepository) OnDuty(ctx context.Context, seenSince time.Time) ([]domain.DriverDuty, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id::text, on_duty_at, last_seen_at, last_lat, last_lng
		FROM drivers
		WHERE on_duty_at IS NOT NULL AND last_seen_at >= $1`, seenSince)
	if err != nil {
		return nil, fmt.Errorf("listing drivers on duty: %w", err)
	}
	out, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (domain.DriverDuty, error) {
		var d domain.DriverDuty
		err := row.Scan(&d.DriverID, &d.Since, &d.LastSeenAt, &d.Lat, &d.Lng)
		return d, err
	})
	if err != nil {
		return nil, fmt.Errorf("reading drivers on duty: %w", err)
	}
	return out, nil
}

// ExpireDuty takes off duty every driver whose app hasn't reported in since
// silentSince, returning who.
func (r *DriverDutyRepository) ExpireDuty(ctx context.Context, silentSince time.Time) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		UPDATE drivers SET on_duty_at = NULL
		WHERE on_duty_at IS NOT NULL AND (last_seen_at IS NULL OR last_seen_at < $1)
		RETURNING id::text`, silentSince)
	if err != nil {
		return nil, fmt.Errorf("ending silent drivers' duty: %w", err)
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("ending silent drivers' duty: %w", err)
	}
	return ids, nil
}
