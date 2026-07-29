import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/recent_pickups_api.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';

RecentPickupsApi _api(
  http.Response Function(http.Request request) responder, {
  List<http.Request>? captured,
}) {
  final client = MockClient((request) async {
    captured?.add(request);
    return responder(request);
  });
  return RecentPickupsApi(
    client: client,
    baseUrl: 'https://api.test',
    tokenGetter: () => 'tok-1',
  );
}

void main() {
  group('RecentPickupsApi.list', () {
    test('sends a bearer token and parses recents', () async {
      final captured = <http.Request>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode({
            'recents': [
              {
                'placeId': 'p1',
                'address': 'Connaught Place, New Delhi',
                'lat': 12.97,
                'lng': 77.6,
                'usedAt': '2026-07-16T00:00:00Z',
              },
            ],
          }),
          200,
        ),
        captured: captured,
      );

      final result = await api.list();

      final request = captured.single;
      check(request.method).equals('GET');
      check(
        request.url.toString(),
      ).equals('https://api.test/me/recent-pickups');
      check(request.headers['Authorization']).equals('Bearer tok-1');

      check(result).length.equals(1);
      check(result.single.address).equals('Connaught Place, New Delhi');
      check(result.single.placeId).equals('p1');
      check(result.single.point.latitude).equals(12.97);
    });

    test('maps an empty place id to null', () async {
      final api = _api(
        (_) => http.Response(
          jsonEncode({
            'recents': [
              {'placeId': '', 'address': 'A', 'lat': 1.0, 'lng': 2.0},
            ],
          }),
          200,
        ),
      );

      final result = await api.list();
      check(result.single.placeId).isNull();
    });

    test('throws on a non-2xx response', () async {
      final api = _api((_) => http.Response('nope', 500));
      await check(api.list()).throws<RecentPickupsApiException>();
    });
  });

  group('RecentPickupsApi.remember', () {
    test('posts the pickup and returns the updated list', () async {
      final captured = <http.Request>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode({
            'recents': [
              {'placeId': 'p1', 'address': 'A', 'lat': 1.0, 'lng': 2.0},
            ],
          }),
          200,
        ),
        captured: captured,
      );

      final result = await api.remember(
        const PickupLocation(
          address: 'A',
          point: GeoPoint(latitude: 1.0, longitude: 2.0),
          placeId: 'p1',
        ),
      );

      final sent = jsonDecode(captured.single.body) as Map<String, dynamic>;
      check(captured.single.method).equals('POST');
      check(sent['placeId']).equals('p1');
      check(sent['address']).equals('A');
      check(sent['lat']).equals(1.0);
      check(result.single.address).equals('A');
    });
  });
}
