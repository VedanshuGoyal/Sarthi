# Sarthi — Flutter + MCP Agent Setup

This doc captures how the Flutter side of the monorepo is wired so an
MCP-capable agent (Claude Code) can see a running app, take screenshots,
inspect the widget tree, and drive it (taps, text entry, hot reload, etc.).

There are two Flutter apps — `apps/user_app/` and `apps/driver_app/`. The MCP
server is project-scoped and connects to a running app by its Dart VM service
port, so it works for **whichever app you launch** (one at a time). Run MCP
commands from inside the app directory you're targeting.

## What's here

- `apps/user_app/lib/main.dart` — customer app, bootstrapped through
  `mcp_toolkit` instead of a bare `runApp()`. (`driver_app` can be wired the
  same way when you need to inspect it.)
- `.mcp.json` — registers the `flutter-mcp-toolkit` MCP server (project scope,
  at the repo root — shared by both apps).
- `.claude/settings.local.json` — pre-approves that server so Claude Code
  doesn't need an interactive trust prompt every session.
- Server binary lives outside this repo, built from source (see below).

## One-time setup (already done, kept here for the next clone/machine)

1. **Create a Flutter app** (skip if the app dir already exists):
   ```bash
   flutter create --project-name user_app --org com.sarthi apps/user_app
   ```

2. **Add the app-side MCP binding**:
   ```bash
   cd apps/user_app && flutter pub add mcp_toolkit
   ```
   In `apps/user_app/lib/main.dart`, replace `runApp(...)` with:
   ```dart
   import 'package:mcp_toolkit/mcp_toolkit.dart';

   Future<void> main() async {
     await MCPToolkitBinding.instance.bootstrapFlutter(
       runApp: () => runApp(const MyApp()),
     );
   }
   ```
   This only activates in debug builds — no-op in release.

3. **Build the MCP server** (no published binary exists; build from source):
   ```bash
   mkdir -p ~/Dev/third_party && cd ~/Dev/third_party
   git clone --depth 1 https://github.com/Arenukvern/mcp_flutter.git
   cd mcp_flutter
   make install && make build
   ```
   This produces:
   `~/Dev/third_party/mcp_flutter/mcp_server_dart/build/flutter-mcp-toolkit-server`

   Requires the Dart SDK on `PATH` (ships with Flutter) — `make` will tell you
   if it's missing.

4. **Register the server with Claude Code**:
   ```bash
   claude mcp add flutter-mcp-toolkit --scope project -- \
     /absolute/path/to/mcp_flutter/mcp_server_dart/build/flutter-mcp-toolkit-server \
     --dart-vm-host=localhost --dart-vm-port=8181 --resources --images --dynamics
   ```
   This writes `.mcp.json` in the repo. The `--dart-vm-port` value here is a
   placeholder — see "Daily workflow" below, it must match the live app each run.

   > **Note on the Claude Code plugin marketplace path**: there's also a
   > `flutter-mcp-toolkit` Claude Code plugin from the same repo
   > (`/plugin marketplace add Arenukvern/mcp_flutter`). As of `4.0.0-dev.1`
   > its manifest has an `agents` field in a format Claude Code's plugin
   > validator rejects, so installing it fails. Building from source and
   > registering manually (above) is the working path until that's fixed
   > upstream.

5. **Trust the server without a prompt** (optional but avoids friction):
   `.claude/settings.local.json`:
   ```json
   {
     "enabledMcpjsonServers": ["flutter-mcp-toolkit"]
   }
   ```
   If this file instead has `"disabledMcpjsonServers": ["flutter-mcp-toolkit"]`
   (e.g. left over from a declined trust prompt), the server's tools will
   silently not load and there's no prompt to fix it — you have to edit this
   file directly and restart.

## Daily workflow

1. **Start the app in debug mode.** Desktop (`macos`) target needs a full
   Xcode install (`xcodebuild` on `PATH`) — Xcode Command Line Tools alone
   aren't enough. If that's not available, web/Chrome works fine for the MCP
   binding and is the easiest target to keep alive during a session:
   ```bash
   cd apps/user_app && flutter run -d chrome --debug
   # or, to inspect the driver app:  cd apps/driver_app && flutter run -d chrome --debug
   ```
   Android emulators work too, but the *first* build downloads NDK/SDK
   platform/CMake (~5–8 min) and the emulator can drop its ADB connection
   during that wait — Chrome avoids this.

2. **Copy the VM service port from the console output**:
   ```
   A Dart VM Service on Chrome is available at: http://127.0.0.1:<PORT>/<TOKEN>=
   ```
   This port is **random every run** — `.mcp.json`'s `--dart-vm-port` must be
   updated to match before Claude Code can connect, since the server process
   is spawned fresh per Claude Code session using those args.

3. **Update `.mcp.json`** with the current port, then restart Claude Code (MCP
   servers and their args are only read at session start; editing the file
   mid-session has no effect on the current session).

4. **Verify the connection** by asking the agent to discover/connect and grab
   a screenshot. Under the hood this is:
   - `fmt_connect_debug_app` with `{"mode": "uri", "uri": "ws://127.0.0.1:<PORT>/<TOKEN>=/ws"}`
     (the full ws URI with token — host:port alone won't upgrade to a websocket)
   - `fmt_capture_ui_snapshot` — returns screenshots (base64 PNG) + widget tree
     + recent errors in one call. Large; if your client errors on payload
     size, decode `screenshots.images[0]` from base64 to a temp PNG and view
     that file directly instead of inlining the JSON.

## Known rough edges

- `flutter-mcp-toolkit-server`'s `--dart-vm-port` is static per `.mcp.json`
  entry, but Flutter's VM service port is dynamic per run. There's no
  auto-discovery wired up yet here — `fmt_discover_debug_apps` returned zero
  targets in testing on macOS (port-scan strategy filtered everything out),
  so the reliable path is: read the port from the `flutter run` console output
  and connect with the explicit `uri` mode.
- macOS `desktop_window` screenshot capture requires Screen Recording
  permission and falls back to `flutter_layer` capture (Flutter's own canvas)
  if that's not granted — `flutter_layer` is sufficient for UI inspection and
  is what worked here without any macOS permission grants.

---

# Backend & database (Go + PostgreSQL)

The Go API in `server/` persists customer accounts (phone-number registration)
to PostgreSQL — the source of truth. Real-time GPS/matchmaking stays in
`internal/memstore`. Full API reference and curl examples live in
`server/README.md`; this section covers local setup end-to-end.

## One-time install (macOS / Homebrew)

We run Postgres in Docker. On macOS the headless, GUI-free way to get a Docker
daemon is **Colima** (Docker Desktop needs a GUI + privileged helper). `psql`
comes from `libpq`.

```bash
brew install colima docker docker-compose libpq
```

`libpq` is keg-only (not symlinked onto `PATH`). Either expose it once:

```bash
brew link --force libpq
# …or add it per-shell:
export PATH="$(brew --prefix libpq)/bin:$PATH"
```

> Note: under a **non-default Homebrew prefix** (here `~/.homebrew`), `libpq`
> builds from source (krb5 + PostgreSQL) — expect a few minutes. `colima`,
> `docker`, and `docker-compose` are relocatable Go binaries and install from
> bottles instantly.

## Daily workflow

```bash
# 1. Start the Docker VM (first boot downloads a disk image; vz on Apple Silicon).
colima start

# 2. Start Postgres — the users table is auto-created on first boot from
#    server/migrations/0001_create_users.up.sql (mounted into initdb.d).
cd server && docker compose up -d        # or: docker-compose up -d

# 3. Run the API.
export DATABASE_URL='postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable'
go run ./cmd/server                       # → listening on :8080
```

If you already have Postgres (no Docker), apply the migration directly:

```bash
psql "$DATABASE_URL" -f server/migrations/0001_create_users.up.sql
```

## Check all registered accounts

```bash
# Via the API:
curl -s localhost:8080/users | python3 -m json.tool

# Straight from the database:
psql "$DATABASE_URL" -c \
  "SELECT id, phone_e164, name, email, date_of_birth, created_at FROM users ORDER BY created_at DESC;"
```

## Point the Flutter app at the backend

`apps/user_app` resolves the base URL per platform
(`lib/core/config/api_config.dart`):

- **web / desktop / iOS simulator** → `http://localhost:8080`
- **Android emulator** → `http://10.0.2.2:8080` (host loopback)
- override anywhere with `flutter run --dart-define=API_BASE_URL=http://host:8080`

## Ola Maps (pickup-location step)

The Round Trip pickup screen uses Ola Maps Places (OAuth 2.0 client
credentials). The **backend** holds the credentials and mints short-lived
bearer tokens; the app fetches one from `GET /maps/token` (authenticated with
the customer's session) and sends it on its Places requests. The client secret
never ships in an app build or the web bundle.

Put the credentials in the git-ignored `server/.env`, which
`./scripts/run-backend.sh` loads:

```bash
# server/.env
OLA_MAPS_CLIENT_ID=your-client-id
OLA_MAPS_CLIENT_SECRET=your-client-secret
```

On the VPS they go in `server/.env.prod` (see `server/deploy/README.md`).
Without them `/maps/token` answers 503 and the search field shows "Map search
isn't set up yet." rather than crashing. The app side lives in
`lib/features/ride/data/ola_maps_authenticator.dart`.

### Google Maps (the "Select on map" pin step)

The pickup screen's **Select on map** option renders a Google map; the pin's
coordinates are reverse-geocoded through the same Ola repository. The Google
Maps **SDK key** is a *native* setting — `--dart-define` can't reach the Android
manifest / iOS `Info.plist` — so it's read from `.env` at build time instead:

```bash
# apps/user_app/.env  (git-ignored)
MAPS_API_KEY=AIza...your_key
```

- **Android** — `android/app/build.gradle.kts` reads `MAPS_API_KEY` from `.env`
  (falling back to `local.properties`) and injects it into the manifest.
- **iOS** — `scripts/run-user-app.sh` mirrors the key into a git-ignored
  `ios/Flutter/Maps.xcconfig` that `Info.plist` references via `$(MAPS_API_KEY)`.
  Building straight from Xcode? Run the script once (or create that file
  manually) so the key is present.

Enable **Maps SDK for Android** and **Maps SDK for iOS** in Google Cloud, then
restrict the key to the app (Android package `com.sarthi.user_app` + your
signing SHA-1). Without a key the app still runs — the map just shows blank
tiles. (Web/`chrome` maps need the JS SDK in `web/index.html` and aren't wired
yet.)

#### Advanced markers (optional)

The route-overview map (`RouteMap`) can render Google's **advanced markers** —
higher-performance pins with richer styling — instead of legacy markers. They
require a **cloud Map ID** (Google Cloud console → *Maps → Map management*).
Create one **per platform you target** (Map type *Android* and/or *iOS*; *and*
a *JavaScript* Map ID if you also run the web build), then pass it as a define.
Unlike `MAPS_API_KEY`, the Map ID reaches the map through the plugin at
runtime, so `--dart-define` *does* carry it to Android and iOS:

```bash
# apps/user_app/.env  (git-ignored) — consumed by --dart-define-from-file
MAPS_MAP_ID=your_map_id
```

When set, `RouteMap` builds `AdvancedMarker`s on a Map-ID'd map; when unset it
transparently falls back to legacy markers, so the Map ID is optional and
nothing breaks without it. Requirements: Android needs the upgraded map
renderer (default since Maps SDK 18.2.0, which the plugin already uses); on the
web this also replaces the deprecated `google.maps.Marker` and clears its
console warning.

## Push notifications (Firebase Cloud Messaging)

Uber-style alerts: **"New ride request"** to every online driver within 50 km
who can take the ride (KYC cleared, right gearbox, app reported in within
10 min); to the customer **"Driver assigned"** on accept, **"Your driver has
arrived"** when the driver marks arrival, and **"Your driver cancelled"** when
the driver hands the ride back (nearby drivers then get the request again
while it's still open). Tapping opens Home (driver) / Activity (customer).

One Firebase project, two Android apps:

1. [Firebase console](https://console.firebase.google.com) → add project (or
   add Firebase to the existing Google Cloud project).
2. Add Android apps `com.sarthi.user_app` and `com.sarthi.driver_app`.
3. Download `google-services.json` (it lists both apps) and copy it to
   **both** `apps/user_app/android/app/` and `apps/driver_app/android/app/`
   (git-ignored). Rebuild the APKs.
4. Project settings → Service accounts → *Generate new private key*. Point
   the server at it: `FCM_CREDENTIALS_FILE=/path/to/key.json` in
   `server/.env` (local) or `server/.env.prod` (VPS, see that file).

Without the JSON the apps build and run with push off; without the key the
server still stores device tokens but sends nothing. Server code:
`internal/service/notify_service.go`, `internal/push/fcm`. App code:
`lib/core/services/push_service.dart` + `lib/features/notifications/`.
Local testing against a fake FCM: set `FCM_BASE_URL`.

## Verified end-to-end (2026-06-27)

`colima start` → `docker compose up -d` → `go run ./cmd/server`, then the
`server/README.md` smoke test:

| Step | Result |
| --- | --- |
| `POST /auth/otp` | `202` |
| `POST /auth/otp/verify` wrong code | `401 {"error":"incorrect verification code"}` |
| `POST /auth/otp/verify` `123456` | `200` |
| `POST /auth/register` | `201` + persisted user (DB-assigned UUID) |
| duplicate phone | `409 {"error":"phone number already registered"}` |
| under-18 DOB | `400 {"error":"you must be at least 18 years old"}` |
| `GET /users` / `SELECT … FROM users` | both list the registered rows |

## Stopping / cleanup

```bash
cd server && docker compose down     # stop Postgres (add -v to wipe the data volume)
colima stop                          # stop the Docker VM
```

## Known rough edges

- `gen_random_uuid()` (used by the `users` PK default) is built into
  PostgreSQL 13+; on older servers enable it with
  `CREATE EXTENSION IF NOT EXISTS pgcrypto;`.
- `GET /users` is intentionally **unauthenticated** for local development — put
  it behind admin auth before deploying.
- OTP is a fixed dev code (`123456`) until an SMS provider is integrated
  (`service.AuthService.RequestOTP`).
