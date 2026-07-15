/// Ola Maps OAuth 2.0 credentials and endpoints, resolved from build-time
/// defines.
///
/// Ola Maps authenticates Places requests with an OAuth 2.0 *client
/// credentials* grant: the app exchanges [clientId] + [clientSecret] at
/// [tokenUrl] for a short-lived bearer token, then sends it on each request.
/// Supply the credentials at build/run time — they are never committed:
///
/// ```
/// flutter run \
///   --dart-define=OLA_MAPS_CLIENT_ID=your_id \
///   --dart-define=OLA_MAPS_CLIENT_SECRET=your_secret
/// ```
///
/// Note: a client secret embedded in a mobile binary can be extracted. For
/// production, prefer minting the token on the Go backend and having the app
/// request it from there — the data layer takes any token provider, so that
/// swap is localised (see `LocationRepository`'s `tokenProvider`).
abstract final class OlaMapsConfig {
  /// Base URL for the Ola Maps Places REST APIs. Overridable for tests/staging.
  static const String baseUrl = String.fromEnvironment(
    'OLA_MAPS_BASE_URL',
    defaultValue: 'https://api.olamaps.io',
  );

  /// OAuth token endpoint (Ola's Keycloak realm) for the client-credentials
  /// grant.
  static const String tokenUrl = String.fromEnvironment(
    'OLA_MAPS_TOKEN_URL',
    defaultValue:
        'https://account.olamaps.io/realms/olamaps/protocol/openid-connect/token',
  );

  /// OAuth client id. Empty when unconfigured — the location step degrades to a
  /// clear "maps isn't set up" message rather than failing opaquely.
  static const String clientId = String.fromEnvironment(
    'OLA_MAPS_CLIENT_ID',
    defaultValue: '',
  );

  /// OAuth client secret.
  static const String clientSecret = String.fromEnvironment(
    'OLA_MAPS_CLIENT_SECRET',
    defaultValue: '',
  );

  /// Whether both credentials are present, so callers can branch before making
  /// requests.
  static bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
}
