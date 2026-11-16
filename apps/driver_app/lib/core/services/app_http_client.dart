import 'dart:async';

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
///    failing every call with a generic error — for good, for a driver
///    still on the document steps, which have no log-out.
class AppHttpClient extends http.BaseClient {
  AppHttpClient({
    http.Client? inner,
    this.timeout = defaultTimeout,
    this.onSessionRejected,
  }) : _inner = inner ?? http.Client();

  /// Generous enough for a KYC photo upload or a bank check on a slow
  /// connection; short enough that a dead one ends.
  static const Duration defaultTimeout = Duration(seconds: 60);

  final http.Client _inner;
  final Duration timeout;
  final void Function(String token)? onSessionRejected;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request).timeout(timeout);
    final onRejected = onSessionRejected;
    final auth = request.headers['Authorization'];
    if (response.statusCode == 401 &&
        onRejected != null &&
        auth != null &&
        auth.startsWith('Bearer ')) {
      onRejected(auth.substring('Bearer '.length));
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
