import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/data/recent_locations_storage.dart';
import 'package:user_app/features/ride/data/recent_pickups_api.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';

/// Builds a repository over a [MockClient] that records the last request and
/// replies with [responder]. [tokenProvider] defaults to a canned token.
LocationRepository _repo(
  http.Response Function(http.Request request) responder, {
  AccessTokenProvider? tokenProvider,
  List<http.Request>? captured,
}) {
  final client = MockClient((request) async {
    captured?.add(request);
    return responder(request);
  });
  return LocationRepository(
    client: client,
    tokenProvider: tokenProvider ?? (() async => 'test-token'),
    baseUrl: 'https://maps.test',
    routesBaseUrl: 'https://routes.test',
    routesApiKey: 'routes-key',
  );
}

/// In-memory [RecentLocationsStorage] for recents tests.
class _MemoryRecentsStorage implements RecentLocationsStorage {
  List<PickupLocation> saved = const [];
  @override
  Future<List<PickupLocation>> read() async => saved;
  @override
  Future<void> write(List<PickupLocation> locations) async => saved = locations;
}

PickupLocation _pickup(String address, {String? placeId}) => PickupLocation(
  address: address,
  point: const GeoPoint(latitude: 12.9, longitude: 77.6),
  placeId: placeId,
);

/// Wraps [client] as a recents API pointed at a stub backend.
RecentPickupsApi _recentsApi(MockClient client) => RecentPickupsApi(
  client: client,
  baseUrl: 'https://api.test',
  tokenGetter: () => 'token',
);

/// A `{recents:[...]}` body from the given addresses.
String _recentsBody(List<String> addresses) => jsonEncode({
  'recents': [
    for (final a in addresses)
      {
        'placeId': a,
        'address': a,
        'lat': 12.9,
        'lng': 77.6,
        'usedAt': '2026-07-16T00:00:00Z',
      },
  ],
});

void main() {
  group('LocationRepository recents (backend-first)', () {
    test('recentPickups returns the backend list and caches it', () async {
      final cache = _MemoryRecentsStorage();
      final repo = LocationRepository(
        recentsCache: cache,
        recentsApi: _recentsApi(
          MockClient((_) async => http.Response(_recentsBody(['A', 'B']), 200)),
        ),
      );

      final result = await repo.recentPickups();

      check(result.map((p) => p.address).toList()).deepEquals(['A', 'B']);
      // Mirrored into the offline cache.
      check(cache.saved.map((p) => p.address).toList()).deepEquals(['A', 'B']);
    });

    test(
      'cachedRecents reads the local cache without touching the backend',
      () async {
        final cache = _MemoryRecentsStorage()
          ..saved = [_pickup('Cached', placeId: 'c')];
        final repo = LocationRepository(
          recentsCache: cache,
          // A client that fails the test if the backend is contacted at all.
          recentsApi: _recentsApi(
            MockClient((_) async => throw StateError('should not hit backend')),
          ),
        );

        final result = await repo.cachedRecents();
        check(result.map((p) => p.address).toList()).deepEquals(['Cached']);
      },
    );

    test(
      'recentPickups falls back to the cache when the backend fails',
      () async {
        final cache = _MemoryRecentsStorage()
          ..saved = [_pickup('Cached', placeId: 'c')];
        final repo = LocationRepository(
          recentsCache: cache,
          recentsApi: _recentsApi(
            MockClient((_) async => http.Response('x', 503)),
          ),
        );

        final result = await repo.recentPickups();
        check(result.map((p) => p.address).toList()).deepEquals(['Cached']);
      },
    );

    test(
      'rememberPickup posts to the backend and caches the response',
      () async {
        final cache = _MemoryRecentsStorage();
        Map<String, dynamic>? sent;
        final repo = LocationRepository(
          recentsCache: cache,
          recentsApi: _recentsApi(
            MockClient((req) async {
              sent = jsonDecode(req.body) as Map<String, dynamic>;
              return http.Response(_recentsBody(['A']), 200);
            }),
          ),
        );

        final result = await repo.rememberPickup(_pickup('A', placeId: 'a'));

        check(sent?['address']).equals('A');
        check(result.map((p) => p.address).toList()).deepEquals(['A']);
        check(cache.saved).length.equals(1);
      },
    );

    test('rememberPickup offline de-dupes and caps into the cache', () async {
      final repo = LocationRepository(
        recentsCache: _MemoryRecentsStorage(),
        maxRecents: 2,
        recentsApi: _recentsApi(
          MockClient((_) async => http.Response('x', 503)),
        ),
      );

      await repo.rememberPickup(_pickup('A', placeId: 'a'));
      await repo.rememberPickup(_pickup('B', placeId: 'b'));
      await repo.rememberPickup(_pickup('A', placeId: 'a')); // repeat → front
      final result = await repo.rememberPickup(_pickup('C', placeId: 'c'));

      // Newest-first, deduped, capped at 2.
      check(result.map((p) => p.address).toList()).deepEquals(['C', 'A']);
    });
  });

  group('LocationRepository.autocomplete', () {
    test('sends input + api key and parses predictions', () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response(
          jsonEncode({
            'predictions': [
              {
                'place_id': 'p1',
                'description': 'MG Road, Bengaluru',
                'structured_formatting': {
                  'main_text': 'MG Road',
                  'secondary_text': 'Bengaluru',
                },
                'geometry': {
                  'location': {'lat': 12.97, 'lng': 77.6},
                },
              },
            ],
          }),
          200,
        ),
        captured: captured,
      );

      final results = await repo.autocomplete('MG Road');

      final request = captured.single;
      check(request.url.path).equals('/places/v1/autocomplete');
      check(request.url.queryParameters['input']).equals('MG Road');
      check(request.url.queryParameters).not((q) => q.containsKey('api_key'));
      check(request.headers['Authorization']).equals('Bearer test-token');

      check(results).length.equals(1);
      check(results.single.primaryText).equals('MG Road');
      check(results.single.point?.latitude).equals(12.97);
    });

    test('returns empty for a too-short query without a request', () async {
      final captured = <http.Request>[];
      final repo = _repo((_) => http.Response('{}', 200), captured: captured);

      check(await repo.autocomplete('MG')).isEmpty();
      check(captured).isEmpty();
    });

    test('propagates a token/authorization failure', () async {
      final repo = _repo(
        (_) => http.Response('{}', 200),
        tokenProvider: () async =>
            throw const LocationException('not authorized'),
      );
      await check(repo.autocomplete('MG Road')).throws<LocationException>();
    });

    test('maps a non-2xx response to a LocationException', () async {
      final repo = _repo((_) => http.Response('nope', 500));
      await check(repo.autocomplete('MG Road')).throws<LocationException>();
    });
  });

  group('LocationRepository.reverseGeocode', () {
    test('parses the first formatted address', () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response(
          jsonEncode({
            'results': [
              {'formatted_address': '12 MG Road, Bengaluru', 'place_id': 'p9'},
            ],
          }),
          200,
        ),
        captured: captured,
      );

      final pickup = await repo.reverseGeocode(
        const GeoPoint(latitude: 12.97, longitude: 77.6),
      );

      check(captured.single.url.queryParameters['latlng']).equals('12.97,77.6');
      check(pickup.address).equals('12 MG Road, Bengaluru');
      check(pickup.placeId).equals('p9');
    });

    test('falls back to coordinates when no address is returned', () async {
      final repo = _repo(
        (_) => http.Response(jsonEncode({'results': []}), 200),
      );

      final pickup = await repo.reverseGeocode(
        const GeoPoint(latitude: 1.5, longitude: 2.5),
      );
      check(pickup.address).equals('1.5,2.5');
    });
  });

  group('LocationRepository.currentLocation', () {
    test('reverse-geocodes the injected device position', () async {
      final repo = LocationRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                {'formatted_address': 'Home, Bengaluru'},
              ],
            }),
            200,
          ),
        ),
        tokenProvider: () async => 'test-token',
        baseUrl: 'https://maps.test',
        positionFetcher: () async =>
            const GeoPoint(latitude: 12.9, longitude: 77.6),
      );

      final pickup = await repo.currentLocation();
      check(pickup.address).equals('Home, Bengaluru');
    });

    test('propagates a permission failure from the fetcher', () async {
      final repo = LocationRepository(
        tokenProvider: () async => 'test-token',
        positionFetcher: () async =>
            throw const LocationPermissionException('denied'),
      );
      await check(repo.currentLocation()).throws<LocationPermissionException>();
    });
  });

  group('LocationRepository.travelTime', () {
    const start = GeoPoint(latitude: 12.9756, longitude: 77.6068);
    const destination = GeoPoint(latitude: 13.1986, longitude: 77.7066);

    /// A one-route Routes API body with the given protobuf-style duration.
    String routesBody(String duration) => jsonEncode({
      'routes': [
        {'duration': duration},
      ],
    });

    test(
      'no departure time: asks Ola and sums the first route\'s legs',
      () async {
        final captured = <http.Request>[];
        final repo = _repo(
          (_) => http.Response(
            jsonEncode({
              'routes': [
                {
                  'legs': [
                    {'duration': 3600},
                    {'duration': 1500},
                  ],
                },
              ],
            }),
            200,
          ),
          captured: captured,
        );

        final eta = await repo.travelTime(
          start: start,
          destination: destination,
        );

        final request = captured.single;
        check(request.method).equals('POST');
        check(request.url.host).equals('maps.test');
        check(request.url.path).equals('/routing/v1/directions');
        check(request.url.queryParameters['origin']).equals('12.9756,77.6068');
        check(
          request.url.queryParameters['destination'],
        ).equals('13.1986,77.7066');
        check(request.headers['Authorization']).equals('Bearer test-token');

        check(eta).equals(const Duration(hours: 1, minutes: 25));
      },
    );

    test('a departure time routes to Google, traffic-aware', () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response(routesBody('5100s'), 200),
        captured: captured,
      );

      final departure = DateTime.now().add(const Duration(hours: 3));
      final eta = await repo.travelTime(
        start: start,
        destination: destination,
        departureAt: departure,
      );

      final request = captured.single;
      check(request.method).equals('POST');
      check(
        request.url.toString(),
      ).equals('https://routes.test/directions/v2:computeRoutes');
      check(request.headers['X-Goog-Api-Key']).equals('routes-key');
      check(request.headers['X-Goog-FieldMask']).equals('routes.duration');

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      check(body['travelMode']).equals('DRIVE');
      check(body['routingPreference']).equals('TRAFFIC_AWARE');
      check(body['departureTime']).equals(departure.toUtc().toIso8601String());
      final origin = body['origin'] as Map<String, dynamic>;
      final latLng =
          (origin['location'] as Map<String, dynamic>)['latLng']
              as Map<String, dynamic>;
      check(latLng['latitude']).equals(12.9756);
      check(latLng['longitude']).equals(77.6068);

      check(eta).equals(const Duration(hours: 1, minutes: 25));
    });

    test('omits a past departure time (Google rejects them)', () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response(routesBody('600s'), 200),
        captured: captured,
      );

      await repo.travelTime(
        start: start,
        destination: destination,
        departureAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      check(body.containsKey('departureTime')).isFalse();
    });

    test(
      'throws when Google is needed but the key is not configured',
      () async {
        final repo = LocationRepository(
          client: MockClient(
            (_) async => http.Response(routesBody('600s'), 200),
          ),
          tokenProvider: () async => 'test-token',
          baseUrl: 'https://maps.test',
          routesBaseUrl: 'https://routes.test',
          routesApiKey: '',
        );
        await check(
          repo.travelTime(
            start: start,
            destination: destination,
            departureAt: DateTime.now().add(const Duration(hours: 5)),
          ),
        ).throws<LocationException>();
      },
    );

    test('throws when no route carries a duration', () async {
      final repo = _repo(
        (_) => http.Response(jsonEncode({'routes': <Object>[]}), 200),
      );
      await check(
        repo.travelTime(start: start, destination: destination),
      ).throws<LocationException>();
    });

    test('throws on a non-2xx response', () async {
      final repo = _repo((_) => http.Response('nope', 403));
      await check(
        repo.travelTime(start: start, destination: destination),
      ).throws<LocationException>();
    });
  });
}
