/// Google Maps Platform key and endpoints, resolved from build-time defines.
///
/// The same `MAPS_API_KEY` that loads the Google Maps SDK for the map picker
/// also authorizes the Routes API, which estimates drive times for the chosen
/// departure time. Supply it at build/run time — never committed:
///
/// ```
/// flutter run --dart-define=MAPS_API_KEY=your_key
/// ```
///
/// Note: an API key embedded in a mobile binary can be extracted; restrict the
/// key to the Maps SDK + Routes API in the Google Cloud console, and prefer
/// proxying Routes calls through the Go backend for production.
abstract final class GoogleMapsConfig {
  /// API key for Google Maps Platform. Empty when unconfigured — drive-time
  /// estimates then fail with a clear message instead of a 403.
  static const String apiKey = String.fromEnvironment('MAPS_API_KEY');

  /// Cloud-based Map ID created in the Google Cloud console (Maps → Map
  /// management). It is the prerequisite for advanced markers on every
  /// platform: the Maps SDK (Android, iOS, and JS) only renders them on a map
  /// instantiated with a Map ID, and each platform needs a Map ID of its own
  /// type (Android / iOS / JavaScript). Unlike [apiKey] — a native setting —
  /// the Map ID reaches the map through the plugin at runtime, so a single
  /// `--dart-define` covers all platforms (see SETUP.md):
  ///
  /// ```
  /// flutter run --dart-define=MAPS_MAP_ID=your_map_id
  /// ```
  ///
  /// Empty when unset — map widgets then fall back to legacy markers, which
  /// still render, so the app works without a Map ID.
  static const String mapId = String.fromEnvironment('MAPS_MAP_ID');

  /// Whether a Map ID is configured, so map widgets can opt into advanced
  /// markers instead of the deprecated legacy ones.
  static bool get advancedMarkersEnabled => mapId.isNotEmpty;

  /// Base URL for the Google Routes API. Overridable for tests/staging.
  static const String routesBaseUrl = String.fromEnvironment(
    'GOOGLE_ROUTES_BASE_URL',
    defaultValue: 'https://routes.googleapis.com',
  );

  static bool get isConfigured => apiKey.isNotEmpty;
}
