/// Ensures the Google Maps JavaScript SDK is present before a map is shown.
///
/// On Android/iOS the SDK ships natively (keyed via the manifest / Info.plist),
/// so this is a no-op there. On web the SDK must be loaded into the page; the
/// web implementation injects the `<script>` tag using the `MAPS_API_KEY`
/// compile-time define (fed from `.env` via `--dart-define-from-file`), so the
/// key stays out of `web/index.html` and out of source control.
///
/// The conditional export swaps in the real web loader only when compiling for
/// web, keeping `dart:js_interop`/`package:web` off the mobile builds.
library;

export 'web_maps_loader_stub.dart'
    if (dart.library.js_interop) 'web_maps_loader_web.dart';
