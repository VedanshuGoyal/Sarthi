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

  /// Base URL for the Google Routes API. Overridable for tests/staging.
  static const String routesBaseUrl = String.fromEnvironment(
    'GOOGLE_ROUTES_BASE_URL',
    defaultValue: 'https://routes.googleapis.com',
  );

  static bool get isConfigured => apiKey.isNotEmpty;
}
