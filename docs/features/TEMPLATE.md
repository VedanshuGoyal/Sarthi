# <Feature name>

<!-- Copy to docs/features/<slug>.md. Bullets and tables only. Delete any
     section that is truly "None" only after writing "None." under it. -->

| | |
|---|---|
| Slug | `<slug>` |
| Status | draft · approved (<who>, <YYYY-MM-DD>) · implemented · shipped (<commit>, <YYYY-MM-DD>) |
| Components | server · user_app · driver_app |
| Risk flags | none · PAYMENTS · KYC (see Risk) |
| Versions | user_app `x.y.z+n` → `…` · driver_app `x.y.z+n` → `…` · server only |

## Goal

- Who gets what, and why now (1–2 lines).

## User stories

- As a <customer | driver | admin>, I can … so that ….

## Contract

### Routes

| Method | Path | Auth | Request | 2xx | Errors |
|---|---|---|---|---|---|
| GET | `/…` | session · driver session · `ADMIN_TOKEN` · public | — | 200 `{…}` | 401, 404 `code` |

### JSON

```json
{}
```

- Money: integer paise, key ends in `Paise`. Never floats.
- Times: RFC 3339. Day windows: Asia/Kolkata (IST, fixed +05:30).
- Keys camelCase; enums are lowercase strings; empty lists are `[]`, not `null`.
- Field rules (required / optional / omitted when …):

### Error codes

| Status | `code` | When |
|---|---|---|
| 400 | `…` | … |

## Migration

- None. — or —
- `server/migrations/NNNN_<name>.up.sql` + `.down.sql`.
- Idempotent (`IF NOT EXISTS`, backfills only touch NULL rows): replayed on every local boot.
- Add the `.up.sql` to `server/docker-compose.yml` initdb mounts.
- Prod: applied by the owner via the rollout script (psql as `sarthi`, one transaction).
- Backfill / lock risk on big tables:

## Push notifications

- None. — or —

| `type` | To | Title / body | Tap opens | Sent when |
|---|---|---|---|---|

## App screens

### user_app

- Screen / widget · entry point · states: loading, empty, error, success.

### driver_app

- None.

## Acceptance tests

Each bullet becomes exactly one test, named here. Tests are written before code.

### Server unit (`go test ./...`)

- [ ] `TestXxx_case` (`internal/service/…_test.go`) — given … when … then ….
- [ ] `TestXxxRoute_…` (`internal/api/…_test.go`) — auth, status codes, JSON keys.

### Repository SQL (`SARTHI_TEST_DATABASE_URL`, local docker DB, rolled back)

- [ ] `TestXxx_Integration` (`internal/repository/…_test.go`) — fixtures → expected deltas.

### Flutter

- [ ] user_app `test/features/<f>/…_test.dart` — view model: ….
- [ ] user_app `test/features/<f>/…_widget_test.dart` — renders …, tap … calls ….
- [ ] driver_app ….

### Local e2e (`./scripts/run-backend.sh`)

```bash
# exact curl calls + expected status/body
```

## Risk

| Area | Touched? | Notes |
|---|---|---|
| Payments (PhonePe orders, webhook, commission, payouts) | no · read-only · **yes** | yes → HUMAN REVIEW REQUIRED |
| Driver KYC (Surepass, DigiLocker, documents, R2, bank numbers, `secret`) | no · read-only · **yes** | yes → HUMAN REVIEW REQUIRED |
| Personal data in responses / logs / pushes | | phones, names, Aadhaar, bank |
| New prod env vars (`/etc/sarthi/sarthi.env` + `server/.env.prod`) | | |
| Auth scope (who can call it) | | |

## Rollout

- Order: server (backup → migrate → redeploy → health) → APKs → publish.
- Migrations:
- Env changes:
- Smoke checks after deploy:
- Rollback: binary auto-rollback in `redeploy.sh`; DB → `.down.sql` or restore `/root/backups/sarthi-<stamp>.sql.gz`.

## Out of scope

-
