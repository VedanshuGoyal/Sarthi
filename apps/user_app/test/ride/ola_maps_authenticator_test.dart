import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/data/ola_maps_authenticator.dart';

/// A token-endpoint stub that hands out `token-1`, `token-2`, … and counts hits.
class _TokenServer {
  int calls = 0;
  List<http.Request> requests = [];

  http.Client client({int expiresIn = 3600}) {
    return MockClient((request) async {
      calls++;
      requests.add(request);
      return http.Response(
        jsonEncode({
          'access_token': 'token-$calls',
          'expires_in': expiresIn,
          'token_type': 'Bearer',
        }),
        200,
      );
    });
  }
}

void main() {
  group('OlaMapsAuthenticator', () {
    test('requests a client-credentials token and returns it', () async {
      final server = _TokenServer();
      final auth = OlaMapsAuthenticator(
        client: server.client(),
        clientId: 'id',
        clientSecret: 'secret',
        tokenUrl: 'https://auth.test/token',
      );

      check(await auth.accessToken()).equals('token-1');

      final request = server.requests.single;
      check(request.method).equals('POST');
      check(request.url.toString()).equals('https://auth.test/token');
      check(request.bodyFields['grant_type']).equals('client_credentials');
      check(request.bodyFields['client_id']).equals('id');
      check(request.bodyFields['client_secret']).equals('secret');
    });

    test('caches the token until it nears expiry', () async {
      final server = _TokenServer();
      var now = DateTime(2026, 7, 15, 12);
      final auth = OlaMapsAuthenticator(
        client: server.client(expiresIn: 3600),
        clientId: 'id',
        clientSecret: 'secret',
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
        clientId: 'id',
        clientSecret: 'secret',
      );

      final results = await Future.wait([
        auth.accessToken(),
        auth.accessToken(),
        auth.accessToken(),
      ]);

      check(results).deepEquals(['token-1', 'token-1', 'token-1']);
      check(server.calls).equals(1);
    });

    test('throws a LocationException when credentials are missing', () async {
      final auth = OlaMapsAuthenticator(
        client: MockClient((_) async => http.Response('{}', 200)),
        clientId: '',
        clientSecret: '',
      );
      await check(auth.accessToken()).throws<LocationException>();
    });

    test('throws when the token endpoint rejects the request', () async {
      final auth = OlaMapsAuthenticator(
        client: MockClient((_) async => http.Response('nope', 401)),
        clientId: 'id',
        clientSecret: 'secret',
      );
      await check(auth.accessToken()).throws<LocationException>();
    });
  });
}
