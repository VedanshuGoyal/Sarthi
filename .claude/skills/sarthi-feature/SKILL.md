---
name: sarthi-feature
description: Feature factory for the Sarthi / MOJUD ride-hailing monorepo (Go server + user_app + driver_app). Use when asked to build, add or ship a feature, route, screen or admin tool in ~/Work/Sarthi. Flow - spec in docs/features/<slug>.md → owner approves → tests first → parallel implementation → verification gates → release checklist → rollout script the owner runs. Never commits, pushes, deploys or ssh-es on its own.
---

# sarthi-feature

Human writes/approves spec + tests → agents implement → human reviews and releases.

## Hard rules

- No `git commit` / `push`, no `ssh vultr`, no `scripts/publish-apps.sh` (it rsyncs to prod), no prod psql. Leave the diff uncommitted unless the owner says "commit".
- Prod (api.mojud.life, ssh alias `vultr`, repo `/root/mojud/Sarthi`) is changed only by the rollout script the **owner** runs.
- **PAYMENTS** (PhonePe, `payment_*`, `payout_*`, commission, webhook) or **KYC** (Surepass, DigiLocker, `driver_kyc_*`, `storage/`, R2, `secret/`, bank numbers) code touched → spec flag + Gate B + "HUMAN REVIEW REQUIRED" at the top of the handoff. Read-only SQL reads of those tables are not "touched"; say so in Risk.
- Other sessions may be editing the repo: `git status` first; never revert or stage files you didn't change.
- Server: layering `domain ← repository/memstore ← service ← api`; money = integer paise; consumer-side interfaces + fakes; stdlib `testing`; IST = the fixed `ist` zone in `service/trip_plan.go`.
- Flutter pinned **3.44.9** (`~/development/flutter`); never upgrade. MVVM + Repository; `checks` for asserts. Never `dart format lib test` repo-wide — format only files you touched.

## 0. Preflight

```bash
cd ~/Work/Sarthi && git status --short && git log --oneline -3
cat CLAUDE.md
(cd server && go vet ./... && go test ./... -count=1 2>&1 | tail -20)   # baseline must be green
```

- Record baselines when apps are in scope: `flutter test` pass counts (user_app ~294, driver_app ~77) and `flutter analyze` issue counts (user_app has pre-existing warnings in `route_map.dart`).

## 1. Spec

- `cp docs/features/TEMPLATE.md docs/features/<slug>.md`; fill every section, `Status: draft`.
- Read the code the feature touches before writing the contract: `server/internal/api/router.go`, the nearest handler/service/repository, `server/migrations/`, the app's `lib/features/<f>/`.
- Contract = routes, exact JSON (example body), error `code`s, migration file names, push `type`s, screens + states.
- Acceptance tests = named list, one bullet per test (server unit, repository SQL, Flutter VM/widget, local e2e curl).
- Set risk flags honestly.

## Gate A — owner approves the spec (mandatory)

- Stop. Show the spec path + a 5-line summary + open questions. Wait.
- Skip only if the owner's request already fixed the contract and said to proceed; write `approved (owner brief, <date>)`.
- On approval: `Status: approved (<who>, <date>)`.

## 2. Tests first

- Write exactly the acceptance-test list; names must match the spec.
- Go:
  - service: `internal/service/<x>_test.go`, fakes for store/presence/clock (`svc.now = func() time.Time {…}`).
  - route: `internal/api/<x>_test.go` via `NewRouter(…)` + `httptest` — auth (401 / 404 when token unset), status codes, decode into `map[string]any` to pin JSON keys.
  - SQL: `internal/repository/<x>_test.go`, skipped unless `SARTHI_TEST_DATABASE_URL` is set, localhost only, inside a tx that is rolled back; assert deltas vs a baseline read so existing rows don't matter.
- Flutter: view model tests with a fake repository; widget tests for loading / empty / error / success and each tap callback.
- Confirm red: `go test ./...` fails to compile or fails on the new tests only.

## Gate B — owner reviews the tests (PAYMENTS / KYC only)

- Show the test diff; wait. Otherwise tests are reviewed with the final diff.

## 3. Implement

- Server first, in this order: migration → `domain` → `repository` → `service` → `api` handler → `router.go` → `cmd/server/main.go` wiring → `server/README.md` endpoint row.
- Local e2e on the server before any app work (contract is then frozen; changing it means updating the spec).
- Apps: one subagent per app, launched in **one message** so they run in parallel. Brief each with:
  - spec path, contract section, test files they must make green, dirs in scope (`apps/<app>/lib/features/<f>/`, `test/…`);
  - constraints: Flutter 3.44.9, MVVM + Repository, no version bump, no commit, no repo-wide format;
  - commands to run (gate 4.3) and report: files changed, test/analyze counts.
- Review subagent output yourself (read the diff) before the gates.

## 4. Verification gates (all must pass; paste the counts in the handoff)

### 4.1 Server

```bash
cd ~/Work/Sarthi/server
test -z "$(gofmt -l .)" && go vet ./... && go test ./... -count=1
go test ./... -count=1 -v 2>&1 | grep -c -- '--- PASS'      # pass count
```

### 4.2 Local DB + e2e

```bash
cd ~/Work/Sarthi
docker info >/dev/null && ADMIN_TOKEN=dev-admin ./scripts/run-backend.sh   # background; replays all migrations
./scripts/status.sh                                                    # :8080 health
(cd server && SARTHI_TEST_DATABASE_URL='postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable' \
  go test ./internal/repository/ -run Integration -count=1 -v)
# then the spec's e2e curl block, e.g.
curl -s -H 'Authorization: Bearer dev-admin' localhost:8080/admin/stats | python3 -m json.tool
```

- :8080 held by a stale server → `ADDR=:8093 ./scripts/run-backend.sh` and curl that port.
- Dev OTP `123456`; local test accounts: customer `+919999900001`, drivers `+919999900011/12`.
- External providers (PhonePe, Surepass, FCM) → local fakes on spare ports via `*_BASE_URL` env vars, never real creds.
- Stop the background server when done; if `server-db-1` was stopped before, `docker compose -f server/docker-compose.yml stop`. No docker → say so in the handoff.

### 4.3 Apps (per app in scope)

```bash
cd ~/Work/Sarthi/apps/<app>
flutter --version | head -1          # must say 3.44.9
flutter pub get && flutter analyze   # no new issues vs baseline
flutter test                         # all pass; count ≥ baseline + new tests
```

## 5. Release checklist (agent prepares, owner executes)

- [ ] Spec `Status: implemented`; spec matches what was built.
- [ ] Version bump per changed app in `apps/<app>/pubspec.yaml` `version: X.Y.Z+N`: feature → minor, fix → patch, `+N` always +1. Server has no version.
- [ ] Release APKs (agent may run; read `DOMAIN` from `server/.env.prod`, sign with `apps/*/android/key.properties`):
  ```bash
  ./scripts/build-user-app-apk.sh && ./scripts/build-driver-app-apk.sh
  ~/Android/Sdk/build-tools/*/apksigner verify --print-certs scripts/user_app-release.apk | grep SHA-1    # e16c67b6…
  ~/Android/Sdk/build-tools/*/apksigner verify --print-certs scripts/driver_app-release.apk | grep SHA-1  # 61022d5f…
  ./scripts/publish-apps.sh --dry-run   # renders scripts/apps-page/dist only
  ```
- [ ] Rollout script: `cp .claude/skills/sarthi-feature/rollout-template.sh docs/features/<slug>-rollout.sh`; set `SLUG`, `MIGRATIONS`, `PUBLISH_APPS`, `smoke()`; `bash -n` it. It does: origin/main check → ssh vultr: `git pull` → `pg_dump` backup → migrations (psql as `sarthi`, `-1`) → `server/deploy/redeploy.sh` (auto-rollback on failed health) → outside `/healthz` + smoke → optional `publish-apps.sh`.
- [ ] Owner commit plan, one commit per component: `feat(server): …`, `feat(user_app): … (X.Y.Z+N)`, `feat(driver_app): … (X.Y.Z+N)`.

## 6. Handoff (final message)

- HUMAN REVIEW REQUIRED line first, if flagged.
- Files changed/created (absolute paths), contract summary (JSON shape), gate results (commands + pass counts), what was not verified.
- Owner steps, in order: review diff → commit → push → `bash docs/features/<slug>-rollout.sh` → on success set spec `Status: shipped (<commit>, <date>)`.
