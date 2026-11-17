package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/sarthi/server/internal/domain"
)

// AdminActionRepository keeps the back office's audit trail (admin_actions).
type AdminActionRepository struct {
	db DB
}

// NewAdminActionRepository wires the repository to a pool (or a transaction).
func NewAdminActionRepository(db DB) *AdminActionRepository {
	return &AdminActionRepository{db: db}
}

// RecordAction appends a to the trail and returns it with its id and time.
// A zero At is stamped by the database.
func (r *AdminActionRepository) RecordAction(ctx context.Context, a domain.AdminAction) (domain.AdminAction, error) {
	details := a.Details
	if details == nil {
		details = map[string]any{}
	}
	var at any
	if !a.At.IsZero() {
		at = a.At
	}
	err := r.db.QueryRow(ctx, `
		INSERT INTO admin_actions (actor, action, target, details, at)
		VALUES ($1, $2, $3, $4, coalesce($5::timestamptz, now()))
		RETURNING id, at`,
		a.Actor, a.Action, a.Target, details, at).Scan(&a.ID, &a.At)
	if err != nil {
		return domain.AdminAction{}, fmt.Errorf("recording admin action: %w", err)
	}
	a.Details = details
	return a, nil
}

// RecentActions returns the latest limit actions, newest first — all of
// them, or those on target when it's set.
func (r *AdminActionRepository) RecentActions(ctx context.Context, target string, limit int) ([]domain.AdminAction, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, actor, action, target, details, at
		FROM admin_actions
		WHERE $1 = '' OR target = $1
		ORDER BY at DESC, id DESC
		LIMIT $2`, target, limit)
	if err != nil {
		return nil, fmt.Errorf("listing admin actions: %w", err)
	}
	out, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (domain.AdminAction, error) {
		var a domain.AdminAction
		err := row.Scan(&a.ID, &a.Actor, &a.Action, &a.Target, &a.Details, &a.At)
		return a, err
	})
	if err != nil {
		return nil, fmt.Errorf("listing admin actions: %w", err)
	}
	return out, nil
}
