# Sarthi

A ride-hailing / driver-aggregator platform, organized as a monorepo.

## Structure

```
server/             Go backend — REST + WebSockets, in-memory real-time state
                    (no Redis), Uber H3 geospatial index, PostgreSQL of record
apps/user_app/      Flutter — customer-facing app
apps/driver_app/    Flutter — driver-facing app
shared/             (optional) shared Dart models/utils via Melos
```

See [`CLAUDE.md`](CLAUDE.md) for backend + frontend conventions and which skills
apply where, and [`SETUP.md`](SETUP.md) for the Flutter + MCP agent workflow.

## Quick start

**Backend**
```bash
cd server
go test ./...
go run ./cmd/api      # once cmd/api/main.go is wired up
```

**Apps** (run one at a time)
```bash
cd apps/user_app   && flutter pub get && flutter run
cd apps/driver_app && flutter pub get && flutter run
```
