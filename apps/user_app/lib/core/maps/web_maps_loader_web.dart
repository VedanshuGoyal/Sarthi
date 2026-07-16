import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Google Maps SDK key, fed from `.env` (`MAPS_API_KEY`) via
/// `--dart-define-from-file`. Empty when unconfigured.
const String _apiKey = String.fromEnvironment('MAPS_API_KEY');

/// Memoises the load so concurrent map screens share one script injection.
Future<void>? _loading;

/// Injects the Google Maps JavaScript SDK once, then completes when it's ready.
///
/// Idempotent: repeat calls await the same load, and a hot restart that kept the
/// SDK on `window` returns immediately. With no key it completes anyway so the
/// map widget can surface its own "couldn't load" state instead of hanging.
Future<void> ensureWebMapsReady() => _loading ??= _load();

Future<void> _load() async {
  if (_alreadyLoaded()) return;
  if (_apiKey.isEmpty) return;

  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..async = true
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=$_apiKey&loading=async';
  script.addEventListener(
    'load',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }.toJS,
  );
  script.addEventListener(
    'error',
    (web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Failed to load the Google Maps JavaScript SDK.'),
        );
      }
    }.toJS,
  );
  web.document.head!.appendChild(script);
  await completer.future;
}

/// True once the `google.maps` namespace exists — e.g. after a hot restart that
/// preserved the previously injected SDK.
bool _alreadyLoaded() {
  final google = globalContext.getProperty('google'.toJS);
  if (google == null) return false;
  return (google as JSObject).has('maps');
}
