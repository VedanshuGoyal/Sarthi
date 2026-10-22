import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/data/ola_maps_authenticator.dart';

/// A `/maps/token` stub that hands out `token-1`, `token-2`, … and counts hits.
class _TokenServer {
  int calls = 0;
  List<http.Request> requests = [];

  http.Client client({int expiresIn = 3600}) {
    return MockClient((request) async {
      calls++;
      requests.add(request);
      return http.Response(
        jsonEncode({'accessToken': 'token-$calls', 'expiresIn': expiresIn}),
        200,
      );
    });
  }
}

/// An authenticator whose backend always answers [status].
OlaMapsAuthenticator _answering(int status) => OlaMapsAuthenticator(
  client: MockClient((_) async => http.Response('{}', status)),
  baseUrl: 'https://api.test',
  tokenGetter: () => 'session',
);

void main() {
  group('OlaMapsAuthenticator', () {
    test('fetches the token from the backend with the session token', () async {
      final server = _TokenServer();
      final auth = OlaMapsAuthenticator(
        client: server.client(),
        baseUrl: 'https://api.test',
        tokenGetter: () => 'session-abc',
      );

      check(await auth.accessToken()).equals('token-1');

      final request = server.requests.single;
      check(request.method).equals('GET');
      check(request.url.toString()).equals('https://api.test/maps/token');
      check(request.headers['Authorization']).equals('Bearer session-abc');
    });

    test('caches the token until it nears expiry', () async {
      final server = _TokenServer();
      var now = DateTime(2026, 7, 15, 12);
      final auth = OlaMapsAuthenticator(
        client: server.client(expiresIn: 3600),
        baseUrl: 'https://api.test',
        tokenGetter: () => 'session',
        refreshLeeway: const Duration(seconds: 30),
        clock: () => now,
      );

      check(await auth.accessToken()).equals('token-1');
      // Well within the hour → served from cache, no second request.
      now = now.add(const Duration(minutes: 30));
      check(await auth.accessToken()).equals('token-1');
      check(server.calls).equals(1);

      // Past (expiry − leeway) → refreshed.
      now = now.add(const Duration(minutes: 30));
      check(await auth.accessToken()).equals('token-2');
      check(server.calls).equals(2);
    });

    test('coalesces concurrent refreshes into one request', () async {
      final server = _TokenServer();
      final auth = OlaMapsAuthenticator(
        client: server.client(),
        baseUrl: 'https://api.test',
        tokenGetter: () => 'session',
      );

      final results = await Future.wait([
        auth.accessToken(),
        auth.accessToken(),
        auth.accessToken(),
      ]);

      check(results).deepEquals(['token-1', 'token-1', 'token-1']);
      check(server.calls).equals(1);
    });

    test(
      'says maps are not set up when the backend has no credentials',
      () async {
        await check(_answering(503).accessToken()).throws<LocationException>(
          (it) => it.has((e) => e.message, 'message').contains("isn't set up"),
        );
      },
    );

    test('asks to sign in again when the session is rejected', () async {
      await check(_answering(401).accessToken()).throws<LocationException>(
        (it) => it.has((e) => e.message, 'message').contains('Sign in again'),
      );
    });

    test('throws when the backend cannot mint a token', () async {
      await check(_answering(502).accessToken()).throws<LocationException>();
    });

    test('throws when the backend is unreachable', () async {
      final auth = OlaMapsAuthenticator(
        client: MockClient((_) async => throw http.ClientException('offline')),
        baseUrl: 'https://api.test',
        tokenGetter: () => 'session',
      );
      await check(auth.accessToken()).throws<LocationException>();
    });

    test('does not cache a failure', () async {
      var fail = true;
      final auth = OlaMapsAuthenticator(
        client: MockClient(
          (_) async => fail
              ? http.Response('{}', 502)
              : http.Response(
                  jsonEncode({'accessToken': 'ok', 'expiresIn': 3600}),
                  200,
                ),
        ),
        baseUrl: 'https://api.test',
        tokenGetter: () => 'session',
      );

      await check(auth.accessToken()).throws<LocationException>();
      fail = false;
      check(await auth.accessToken()).equals('ok');
    });
  });
}
