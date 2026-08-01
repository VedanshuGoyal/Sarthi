# scripts/

Convenience scripts for running the Sarthi stack locally. Run them from
anywhere — each resolves the repo root itself. All are `chmod +x`.

| Script | What it does |
|--------|--------------|
| `run-backend.sh` | Brings up Postgres (Docker), waits until it's ready, applies all `migrations/*.up.sql` (idempotent), then runs the Go API server on `:8080`. Ctrl-C stops the server; the DB container keeps running. |
| `run-user-app.sh [device]` | Runs the customer Flutter app (`apps/user_app`) in debug. Defaults to `chrome`. |
| `run-driver-app.sh [device]` | Runs the driver Flutter app (`apps/driver_app`) in debug. Defaults to `chrome`. |
| `build-user-app-apk.sh [mode]` | Builds the customer app's APK against the deployed VPS backend (`DOMAIN` read from `server/.env.prod`) and copies it into `scripts/`. `release` by default, or `debug`. |
| `status.sh` | Read-only health check: is Docker/Postgres up and is the Go server answering `/healthz`? |

## Typical session

```bash
./scripts/run-backend.sh          # terminal 1 — DB + API
./scripts/run-user-app.sh         # terminal 2 — customer app (Chrome)
./scripts/status.sh               # anytime — quick health check
```

Target a different Flutter device by passing its id (see `flutter devices`):

```bash
./scripts/run-user-app.sh macos       # desktop (needs full Xcode)
./scripts/run-driver-app.sh chrome
```

## Notes

- **Backend DSN/port** are overridable via env:
  `DATABASE_URL=... ADDR=:9090 ./scripts/run-backend.sh`.
- **Only one Flutter app** should be attached to the flutter-mcp-toolkit server
  at a time — run the user app *or* the driver app when inspecting via the agent.
- After launching an app, copy the `Dart VM Service ... http://127.0.0.1:<PORT>`
  line into `.mcp.json` if you're using the MCP agent — see `../SETUP.md`.
- Health-check details and manual commands live in `../server/docs/service-health.md`.
