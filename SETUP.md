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
