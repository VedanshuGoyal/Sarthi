import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The app's HTTP client: the repositories' one transport, adding what
/// every request needs and none of them should have to remember.
///
///  * **A time limit.** Nothing else bounds a request: on a phone moving
///    between Wi-Fi and mobile data a socket can hang for minutes, leaving
///    the screen's spinner up. Past [timeout] the request fails with a
///    [TimeoutException], which every repository already reports as "can't
///    reach the server".
///  * **A rejected session.** A 401 to a request that carried a bearer
///    token means the session has expired or was revoked. [onSessionRejected]
///    hears about it, with that token, so the app can sign out instead of
///    failing every call with a generic error until the customer finds the
///    log-out button. Left null for third-party APIs.
///  * **Who is calling.** [headers] go on every request that doesn't set
///    them itself — for the backend, the app and build (`X-App`, `X-Build`).
///  * **An unsupported build.** A 426 `update_required` means the backend no
///    longer serves this build. [onUpdateRequired] hears about it, with the
///    reply's `downloadUrl`, so the app can show its update screen.
class AppHttpClient extends http.BaseClient {
  AppHttpClient({
    http.Client? inner,
    this.timeout = defaultTimeout,
    this.headers = const {},
    this.onSessionRejected,
    this.onUpdateRequired,
  }) : _inner = inner ?? http.Client();

  /// Generous enough for a KYC photo upload or a bank check on a slow
  /// connection; short enough that a dead one ends.
  static const Duration defaultTimeout = Duration(seconds: 60);

  final http.Client _inner;
  final Duration timeout;
  final Map<String, String> headers;
  final void Function(String token)? onSessionRejected;
  final void Function(String? downloadUrl)? onUpdateRequired;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    headers.forEach(
      (name, value) => request.headers.putIfAbsent(name, () => value),
    );
    final response = await _inner.send(request).timeout(timeout);
    final onRejected = onSessionRejected;
    final auth = request.headers['Authorization'];
    if (response.statusCode == 401 &&
        onRejected != null &&
        auth != null &&
        auth.startsWith('Bearer ')) {
      onRejected(auth.substring('Bearer '.length));
    }
    final onUpdate = onUpdateRequired;
    if (response.statusCode == 426 && onUpdate != null) {
      return _checkUpdateRequired(response, onUpdate);
    }
    return response;
  }

  /// Reads a 426's body for its `code` and `downloadUrl`, then hands the
  /// caller an identical response, since the body can only be read once.
  Future<http.StreamedResponse> _checkUpdateRequired(
    http.StreamedResponse response,
    void Function(String? downloadUrl) onUpdate,
  ) async {
    final bytes = await response.stream.toBytes().timeout(timeout);
    try {
      final body = jsonDecode(utf8.decode(bytes));
      if (body is Map && body['code'] == 'update_required') {
        final url = body['downloadUrl'];
        onUpdate(url is String && url.isNotEmpty ? url : null);
      }
    } on FormatException {
      // Not our backend's envelope; nothing to act on.
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
