import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Google Maps SDK key, fed from `.env` (`MAPS_API_KEY`) via
/// `--dart-define-from-file`. Empty when unconfigured.
const String _apiKey = String.fromEnvironment('MAPS_API_KEY');

/// Memoises the load so concurrent map screens share one script injection.
Future<void>? _loading;

/// Libraries the map widgets rely on. With `loading=async` the bootstrap script
/// defines almost nothing up front — a library's members (e.g.
/// `google.maps.MapTypeId`, which the plugin reads synchronously while building
/// a map) only exist once that library has been imported. Importing them here,
/// before any `GoogleMap` builds, is what keeps the plugin from reading an
/// `undefined` `MapTypeId.ROADMAP`.
const _libraries = ['maps', 'marker'];

/// Injects the Google Maps JavaScript SDK once, then completes when it's ready.
///
/// Idempotent: repeat calls await the same load, and a hot restart that kept the
/// SDK on `window` returns immediately. With no key it completes anyway so the
/// map widget can surface its own "couldn't load" state instead of hanging. On
/// failure the memoised load is cleared so a later call can retry.
Future<void> ensureWebMapsReady() =>
    _loading ??= _load().catchError((Object error) {
      _loading = null;
      throw error;
    });

Future<void> _load() async {
  if (!_alreadyLoaded()) {
    if (_apiKey.isEmpty) return;
    await _injectScript();
  }
  await _importLibraries();
}

Future<void> _injectScript() async {
  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..async = true
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$_apiKey&loading=async';
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

/// Awaits `google.maps.importLibrary(...)` for each needed library so their
/// members are populated before a map builds. A no-op on a legacy (non-async)
/// SDK that has no `importLibrary` and already defines everything up front.
Future<void> _importLibraries() async {
  final google = globalContext.getProperty('google'.toJS) as JSObject?;
  if (google == null || !google.has('maps')) return;
  final maps = google.getProperty('maps'.toJS) as JSObject;
  if (!maps.has('importLibrary')) return;
  for (final library in _libraries) {
    await maps.callMethod<JSPromise>('importLibrary'.toJS, library.toJS).toDart;
  }
}

/// True once the `google.maps` namespace exists — e.g. after a hot restart that
/// preserved the previously injected SDK.
bool _alreadyLoaded() {
  final google = globalContext.getProperty('google'.toJS);
  if (google == null) return false;
  return (google as JSObject).has('maps');
}
