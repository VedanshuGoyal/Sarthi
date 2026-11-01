# Admin stats for the ops dashboard

| | |
|---|---|
| Slug | `admin-stats` |
| Status | implemented (pilot of the sarthi-feature factory) — contract from owner brief, 2026-11-01; owner to review |
| Components | server only |
| Risk flags | none — reads payment and KYC columns, changes no payment or KYC code |
| Versions | server only; no app changes |

## Goal

- One admin call returns the counts an ops dashboard needs: accounts, KYC queue, who's on duty, bookings by status, completed-ride money for today / 7 / 30 days, payouts owed.

## User stories

- As an admin, I can see how many customers and drivers exist and how many drivers sit in each KYC status.
- As an admin, I can see how many bookings are open, taken, running, done, cancelled or expired right now.
- As an admin, I can see completed rides, gross fare and MOJUD's commission for today, the last 7 days and the last 30 days.
- As an admin, I can see the total owed to drivers in payouts.

## Contract

### Routes

| Method | Path | Auth | Request | 2xx | Errors |
|---|---|---|---|---|---|
| GET | `/admin/stats` | `Authorization: Bearer <ADMIN_TOKEN>` (same `requireAdmin` as `/admin/kyc`) | — | 200 body below, `Cache-Control: no-store` | 401 `admin token required` · 404 when `ADMIN_TOKEN` unset · 500 `could not load stats` |

### JSON

```json
{
  "asOf": "2026-11-01T12:00:00+05:30",
  "commissionPercent": 13,
  "users": { "customers": 12, "drivers": 5 },
  "driversByKyc": { "incomplete": 1, "submitted": 1, "verified": 3, "rejected": 0 },
  "driversOnDuty": 2,
  "bookingsByStatus": {
    "open": 2, "accepted": 1, "inProgress": 0,
    "completed": 30, "cancelled": 4, "expired": 6, "total": 43
  },
  "completedRides": {
    "today":      { "from": "2026-11-01T00:00:00+05:30", "rides": 1,  "grossFarePaise": 27800,  "commissionPaise": 3614 },
    "last7Days":  { "from": "2026-10-26T00:00:00+05:30", "rides": 6,  "grossFarePaise": 166800, "commissionPaise": 21684 },
    "last30Days": { "from": "2026-10-03T00:00:00+05:30", "rides": 30, "grossFarePaise": 834000, "commissionPaise": 108420 }
  },
  "payoutsDue": { "drivers": 2, "rides": 3, "amountPaise": 60291 }
}
```

- `asOf`: server time of the read, in IST (+05:30).
- `commissionPercent`: `COMMISSION_PERCENT` (basis points / 100; 13 by default; may be fractional, e.g. 12.5). A percentage, not money.
- `users.customers` = rows in `users`; `users.drivers` = rows in `drivers`.
- `driversByKyc`: `drivers.kyc_status` counts; all four keys always present.
- `driversOnDuty`: drivers in the in-memory presence index (`memstore.DriverTracker.Count`) — went online and haven't gone offline. Resets to 0 on a server restart until apps re-report (every 20 s on duty). Omitted if no presence index is wired.
- `bookingsByStatus` (all keys always present):
  - `open` = `requested` and still taking drivers (starts ≥ 30 min from now).
  - `expired` = `requested` and closed to drivers: `scheduled_at < now + 30 min` — the same rule `BookingService.ListMine` uses (`closedToDrivers`, `acceptCutoff`). Derived, never stored.
  - `accepted` = `accepted` + `arrived` (driver assigned, trip not started).
  - `inProgress` = `in_progress`; `completed`; `cancelled`.
  - `total` = every booking row (equals the sum unless an unknown status exists).
- `completedRides` windows are IST calendar days ending now, by `completed_at`, status `completed`:
  - `today` from today 00:00 IST; `last7Days` from 00:00 IST six days ago (7 days incl. today); `last30Days` from 00:00 IST 29 days ago.
  - `grossFarePaise` = sum of `fare_paise`.
  - `commissionPaise` = `round(grossFarePaise × commission)` at the current rate, rounded half-up like `PaymentService.commission`. An estimate on fares, not the commission actually booked on payments.
- `payoutsDue`: same filter as `GET /admin/payouts/due` at now — paid, not paid out, driver still on the row. `amountPaise` = Σ(`paid_paise` − `commission_paise`); `drivers` = distinct drivers owed; `rides` = rides owed.

### Error codes

| Status | `code` | When |
|---|---|---|
| 401 | — | missing / wrong admin token |
| 404 | — | `ADMIN_TOKEN` not configured |
| 500 | — | DB error (logged as `admin: reading stats`) |

## Migration

- None. Existing indexes are enough at current volumes; this is one query of aggregate scans.

## Push notifications

- None.

## App screens

- None. (A Stats tab on the `/admin` web page is a possible follow-up.)

## Acceptance tests

### Server unit (`go test ./...`)

- [x] `TestStats_istWindows` (`internal/service/stats_service_test.go`) — 2026-10-31 19:30 UTC → today 1 Nov 00:00 IST, 7-day from 26 Oct, 30-day from 3 Oct, closes-before = now + 30 min, `asOf` in IST.
- [x] `TestStats_expiredMatchesListMine` — a ride starting 1 ns before the cutoff is `closedToDrivers`, one starting at it is not, so `scheduled_at < closesBefore` matches ListMine.
- [x] `TestStats_commissionAtRate` — 12 345 paise at 13 % → 1 605; at 12.5 % → 1 543; `commissionPercent` 13 / 12.5.
- [x] `TestStats_commissionMatchesPayments` — the stats rounding equals `PaymentService.commission` for a spread of amounts and rates.
- [x] `TestStats_onDuty` — counter 3 → `driversOnDuty` 3; no counter → nil.
- [x] `TestStats_storeError` — store error is returned.
- [x] `TestAdminStatsRoute_requiresToken` (`internal/api/admin_stats_test.go`) — no token / wrong token → 401; `ADMIN_TOKEN` unset → 404.
- [x] `TestAdminStatsRoute_shape` — 200, `Cache-Control: no-store`, every key above present with the store's numbers.
- [x] `TestAdminStatsRoute_storeError` — 500 `could not load stats`.

### Repository SQL (`SARTHI_TEST_DATABASE_URL`, local docker DB, rolled back)

- [x] `TestStatsRepository_Integration` (`internal/repository/stats_repository_test.go`) — inside a rolled-back tx: 2 customers, 4 drivers (one per KYC status), 13 bookings across statuses/windows/boundaries, one payout. Deltas vs a baseline read: customers +2, drivers +4, each KYC +1, open +2 (incl. one exactly at the cutoff), expired +1, accepted +2, inProgress +1, completed +6, cancelled +1, total +13, today 2 rides / 11 000, last7 4 / 36 000, last30 5 / 66 000, payouts due 2 drivers / 2 rides / 13 050.

### Local e2e (`ADMIN_TOKEN=dev-admin ./scripts/run-backend.sh`)

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/admin/stats                                    # 401
curl -s -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer nope' localhost:8080/admin/stats    # 401
curl -s -H 'Authorization: Bearer dev-admin' localhost:8080/admin/stats | python3 -m json.tool          # 200, shape above
```

## Risk

| Area | Touched? | Notes |
|---|---|---|
| Payments | read-only | sums `fare_paise`, `paid_paise`, `commission_paise`, `payout_id`; no change to PhonePe, payment or payout code |
| Driver KYC | read-only | counts `kyc_status`; no change to KYC code |
| Personal data | none | counts and paise only — no names, phones, ids |
| New prod env vars | none | uses existing `ADMIN_TOKEN`, `COMMISSION_PERCENT` |
| Auth scope | admin token only | same guard as every `/admin/*` route |

## Rollout

- Order: server only. No migration, no env change, no APKs.
- Run: `bash docs/features/admin-stats-rollout.sh` after pushing (backup → `server/deploy/redeploy.sh` → health → smoke).
- Smoke: `/admin/stats` without token → 401; with `~/Documents/MOJUD_Keys/sarthi-admin-token.txt` → 200 JSON.
- Rollback: `redeploy.sh` restores the previous binary on a failed health check; nothing in the DB changes.

## Out of scope

- Admin web page tab, charts, history/time series, per-driver or per-city breakdowns.
- Commission actually booked on payments (vs. estimated on fares); paid vs unpaid split.
- "Fresh" on-duty count (presence entries left by apps closed without going offline).
