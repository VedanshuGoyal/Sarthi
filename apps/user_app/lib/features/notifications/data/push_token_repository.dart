import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

/// Raised when the backend can't be reached or refuses a token change.
class PushTokenException implements Exception {
  const PushTokenException(this.message);
  final String message;
  @override
  String toString() => 'PushTokenException: $message';
}

/// Tells the backend which install to notify for this account
/// (`PUT /me/push-token`) and when to stop (`DELETE /me/push-token`).
///
/// The sole data-access seam for push registration, per the repository
/// guideline.
class PushTokenRepository {
  PushTokenRepository({
    http.Client? client,
    String? baseUrl,
    String? Function()? tokenGetter,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _tokenGetter = tokenGetter ?? _noToken;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token from in-memory auth state.
  final String? Function() _tokenGetter;

  static const String _path = '/me/push-token';

  static String? _noToken() => null;

  /// Registers [pushToken] for the signed-in customer.
  Future<void> save(String pushToken) => _send('PUT', pushToken);

  /// Unregisters [pushToken]; call before the session is revoked.
  Future<void> delete(String pushToken) => _send('DELETE', pushToken);

  Future<void> _send(String method, String pushToken) async {
    final session = _tokenGetter();
    final request = http.Request(method, Uri.parse('$_baseUrl$_path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (session != null) 'Authorization': 'Bearer $session',
      })
      ..body = jsonEncode({'token': pushToken});
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } catch (_) {
      throw const PushTokenException("Can't reach the server.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PushTokenException(
        'Updating notifications failed (${response.statusCode}).',
      );
    }
  }
}
