import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import 'location_repository.dart';

/// Fetches and caches Ola Maps bearer tokens from the Sarthi backend
/// (`GET /maps/token`).
///
/// The backend alone holds the Ola OAuth client secret and mints short-lived
/// tokens with it, so nothing extractable ships in the app or web bundle. The
/// request is authorized with the customer's session token, read on demand
/// from in-memory auth state.
///
/// Exposes [accessToken], which returns a cached token while it's still valid
/// and otherwise fetches a fresh one. A single in-flight fetch is shared across
/// concurrent callers (single-flight), so a burst of searches issued before the
/// first token arrives triggers exactly one request. Failures surface as
/// [LocationException] so the UI shows one consistent message.
class OlaMapsAuthenticator {
  OlaMapsAuthenticator({
    http.Client? client,
    String? baseUrl,
    String? Function()? tokenGetter,
    this._refreshLeeway = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _tokenGetter = tokenGetter ?? _noToken,
       _now = clock ?? DateTime.now;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current session token. Returns null when unauthenticated (the
  /// backend then rejects the request).
  final String? Function() _tokenGetter;

  /// How far before the real expiry we treat a token as stale, so a request
  /// never goes out with a token about to expire in transit.
  final Duration _refreshLeeway;
  final DateTime Function() _now;

  static const String _path = '/maps/token';

  /// Default token getter when none is injected — always unauthenticated.
  static String? _noToken() => null;

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
    final session = _tokenGetter();

    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$_baseUrl$_path'),
        headers: {if (session != null) 'Authorization': 'Bearer $session'},
      );
    } catch (_) {
      throw const LocationException(
        "Can't reach the maps service. Check your connection and try again.",
      );
    }

    switch (response.statusCode) {
      case >= 200 && < 300:
        break;
      case 401:
        throw const LocationException(
          'Your session has expired. Sign in again to search for places.',
        );
      case 503:
        throw const LocationException("Map search isn't set up yet.");
      default:
        throw const LocationException(
          'Map search authorization failed. Please try again.',
        );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const LocationException('Unexpected authorization response.');
    }
    final token = decoded['accessToken'];
    if (token is! String || token.isEmpty) {
      throw const LocationException('Authorization response carried no token.');
    }

    final expiresIn = decoded['expiresIn'];
    final seconds = expiresIn is num ? expiresIn.toInt() : 3600;
    _token = token;
    _expiresAt = _now()
        .add(Duration(seconds: seconds))
        .subtract(_refreshLeeway);
    return token;
  }
}
