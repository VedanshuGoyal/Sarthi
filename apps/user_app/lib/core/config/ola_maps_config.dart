/// Ola Maps endpoint, resolved from build-time defines.
///
/// The app holds no Ola credentials. It fetches short-lived bearer tokens from
/// the Sarthi backend (`GET /maps/token`, see `OlaMapsAuthenticator`), which
/// alone holds the OAuth client secret, and sends them on its Places requests
/// to [baseUrl].
abstract final class OlaMapsConfig {
  /// Base URL for the Ola Maps Places REST APIs. Overridable for tests/staging.
  static const String baseUrl = String.fromEnvironment(
    'OLA_MAPS_BASE_URL',
    defaultValue: 'https://api.olamaps.io',
  );
}
