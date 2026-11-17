# Sarthi — Monorepo Guidelines

Sarthi is a ride-hailing / driver-aggregator platform in a single monorepo.
These are the conventions for the whole repo. Follow them when writing or
reviewing code, and apply the section that matches the directory you're in.

## Repository layout

```
server/             Go backend — REST + WebSockets
server/deploy/      VPS setup + redeploy.sh (systemd + Caddy, no Docker on prod)
server/migrations/  numbered SQL migrations (NNNN_name.up/down.sql)
apps/user_app/      Flutter — customer app, ships as "MOJUD"
apps/driver_app/    Flutter — driver app, ships as "MOJUD Driver"
shared/             (optional) shared Dart models/utils via Melos
scripts/            run / build-APK / publish-apps scripts (see scripts/README.md)
docs/features/      feature specs + rollout scripts (sarthi-feature skill)
.agents/skills/     installed skill packs (golang-*, flutter-*, dart-*)
.claude/skills/     symlinks to the above + sarthi-feature
.mcp.json           project-scoped flutter-mcp-toolkit server
```

## Product

- Driver-on-demand: a customer books a trained driver for **their own car**
  (round trip by the hour, one-way, multi-stop).
- Brand is **MOJUD**: `user_app` = "MOJUD" (`com.sarthi.user_app`),
  `driver_app` = "MOJUD Driver" (`com.sarthi.driver_app`). Package ids stay
  `com.sarthi.*`.
- Live integrations: UPI payments (PhonePe), driver KYC (Surepass /
  DigiLocker), push (FCM), KYC file storage (S3-compatible), maps (Ola + Google),
  OTP SMS (Fast2SMS).
- Prod API `api.mojud.life`; APKs are side-loaded from `apps.mojud.life`
  (no Play Store yet).

## Working in this repo

- **This repo is public.** Never commit server IPs, tokens, key paths,
  merchant ids or `.env*` contents.
- New feature / route / screen / admin tool → use the **`sarthi-feature`**
  skill (spec → tests → implement → gates → rollout script).
- Run `git status` first: other sessions may be editing. Never stage or revert
  files you didn't change.
- Flutter is pinned to **3.44.9** — never upgrade. Never run
  `dart format lib test` repo-wide; format only files you touched.
- Version bump in `apps/<app>/pubspec.yaml`: feature → minor, fix → patch,
  `+N` always +1.
- Prod is changed only by a rollout script the owner approves/runs
  (`docs/features/<slug>-rollout.sh`). Prod migrations are applied with
  `psql` as the `sarthi` user, not `setup-vps.sh migrations`.
  `scripts/publish-apps.sh` also touches prod.
- PAYMENTS or KYC code touched → flag "HUMAN REVIEW REQUIRED".

## Which skills to use where

Skills are installed repo-wide; pick by the subtree you're editing:

- **`server/**` (Go):** lean on the `golang-*` skills. `golang-how-to` is the
  orchestrator — it routes to the right ones (e.g. `golang-concurrency` for the
  memstore RWMutex maps, `golang-database` for pgx, `golang-grpc`/`net/http`
  for transport, `golang-testing` for tests). Honor the backend constraints
  below.
- **`apps/**` (Flutter):** use the `flutter-*` skills (responsive layout,
  widget previews, architecture best practices, integration tests) and the
  Flutter guidelines below.

---

# Backend (`server/`) — Go

## Architecture constraints
- **No Redis.** All real-time state (live driver locations, active ride state)
  lives in-memory in `internal/memstore`, guarded by `sync.RWMutex` maps.
- **Geospatial indexing via Uber H3** (`github.com/uber/h3-go/v4`), wrapped in
  `pkg/geo`. Driver locations are bucketed by H3 cell so "find nearby drivers"
  touches only the relevant cells — this replaces Redis `GEORADIUS`.
- **PostgreSQL is the source of truth** for anything that must survive a
  restart (users, drivers, completed rides, financials). memstore is hot,
  rebuildable state — never the system of record.
- **Transport:** REST for CRUD/auth, WebSockets for high-frequency GPS ingestion
  and real-time matchmaking.

## Layering (talk inward only)
`domain` (pure structs) ← `memstore` / `repository` (state & persistence) ←
`service` (business logic) ← `api` / `websocket` (transport). Handlers call
services; services call memstore/repository; nothing reaches back outward.

## Conventions
- Money is stored as integer minor units (cents), never floats.
- Keep H3 out of every package except `pkg/geo`; others use the `geo.Cell` alias.
- Tests use the standard `testing` package; cover concurrency-sensitive code.

---

# Frontend (`apps/`) — Flutter

These conventions apply to both `user_app` and `driver_app`. Each app uses a
**feature-first** layout (`lib/core/`, `lib/features/<feature>/`).

## 1. Design for Constraints
Avoid fixed dimensions (e.g. `width: 300`). Build responsive layouts instead:
- **Abstract**: keep UI components decoupled from global state.
- **Measure**: use `LayoutBuilder` for a widget's local constraints, or `MediaQuery.of(context)` for the whole app window.
- **Branch**: use conditional logic to return different layouts (e.g. `Row` on desktop, `Column` on mobile) based on the measured constraints.

## 2. Debug Using DevTools
- Use the Flutter DevTools **Inspector** to visualize the widget tree and find overflow/layout issues.
- With the Dart/Flutter MCP server connected, fetch runtime errors and inspect the widget tree directly to diagnose and fix issues without manual reproduction.

## 3. Build Reusable Widgets
- Widgets should only render data and emit events via callbacks — no DB calls or API requests inside a widget.
- Use **Widget Previews** to exercise a component's states (loading, error, success) without running the full app.
- Use the Flutter "add widget previews" skill to generate these consistently.

## 4. Layered Architecture (MVVM)
- **View**: UI widgets only.
- **View Model**: `ChangeNotifier`-based; transforms data for the UI and owns local state (e.g. `isLoading`).
- **Data Layer**: talks to external services (network, disk, plugins) — e.g. `core/services/websocket_service.dart`.

## 5. Repository Pattern
- A `Repository` class is the sole interface for data access.
- View Models talk only to the Repository — never directly to a server, database, or plugin. The Repository is the single source of truth.

## 6. Cross-Platform Support
- Prefer community packages from pub.dev to abstract platform differences (e.g. Apple Pay vs Google Pay).
- Use an MCP-connected pub.dev search so docs/API usage reflect current package versions, not stale training data.

## 7. Testing
- **Unit tests**: validate logic in individual classes/functions; use the `checks` package for readable assertions.
- **Widget tests**: verify UI behavior (taps, text rendering) without a physical device.
- **Integration tests**: drive the app on a real/physical device to capture full user journeys (see the Flutter Integration Testing skill).
