import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/ola_maps_config.dart';
import 'location_repository.dart';

/// Mints and caches Ola Maps OAuth 2.0 bearer tokens (client-credentials grant).
///
/// Exposes [accessToken], which returns a cached token while it's still valid
/// and otherwise fetches a fresh one. A single in-flight fetch is shared across
/// concurrent callers (single-flight), so a burst of searches issued before the
/// first token arrives triggers exactly one token request. Failures surface as
/// [LocationException] so the UI shows one consistent message.
class OlaMapsAuthenticator {
  OlaMapsAuthenticator({
    http.Client? client,
    String? clientId,
    String? clientSecret,
    String? tokenUrl,
    this._refreshLeeway = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clientId = clientId ?? OlaMapsConfig.clientId,
       _clientSecret = clientSecret ?? OlaMapsConfig.clientSecret,
       _tokenUrl = tokenUrl ?? OlaMapsConfig.tokenUrl,
       _now = clock ?? DateTime.now;

  final http.Client _client;
  final String _clientId;
  final String _clientSecret;
  final String _tokenUrl;

  /// How far before the real expiry we treat a token as stale, so a request
  /// never goes out with a token about to expire in transit.
  final Duration _refreshLeeway;
  final DateTime Function() _now;

  String? _token;
  DateTime? _expiresAt;
  Future<String>? _inFlight;

  /// Returns a valid bearer token, reusing the cached one until it nears expiry.
  Future<String> accessToken() {
    final token = _token;
    final expiresAt = _expiresAt;
    if (token != null && expiresAt != null && _now().isBefore(expiresAt)) {
      return Future.value(token);
    }
    // Single-flight: coalesce concurrent refreshes onto one request.
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<String> _fetch() async {
    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      throw const LocationException(
        "Map search isn't set up. Add Ola Maps OAuth credentials.",
      );
    }

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_tokenUrl),
        // A Map body is form-encoded by `http`, as the OAuth token endpoint
        // expects (application/x-www-form-urlencoded).
        body: {
          'grant_type': 'client_credentials',
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'scope': 'openid',
        },
      );
    } catch (_) {
      throw const LocationException(
        "Can't reach the maps service. Check your connection and try again.",
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const LocationException(
        'Map search authorization failed. Please try again.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const LocationException('Unexpected authorization response.');
    }
    final token = decoded['access_token'];
    if (token is! String || token.isEmpty) {
      throw const LocationException('Authorization response carried no token.');
    }

    final expiresIn = decoded['expires_in'];
    final seconds = expiresIn is num ? expiresIn.toInt() : 3600;
    _token = token;
    _expiresAt = _now()
        .add(Duration(seconds: seconds))
        .subtract(_refreshLeeway);
    return token;
  }
}
