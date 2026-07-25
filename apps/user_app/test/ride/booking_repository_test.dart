import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/round_trip_booking.dart';
import 'package:user_app/features/ride/domain/transmission.dart';

const _pickup = PickupLocation(
  address: 'MG Road, Bengaluru',
  point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
  placeId: 'p1',
);

final _booking = RoundTripBooking(
  pickup: _pickup,
  hours: 4,
  scheduledAt: DateTime(2026, 7, 20, 9, 15),
  carType: CarType.sedan,
  transmission: Transmission.automatic,
  fare: 440,
);

BookingRepository _repo(
  http.Response Function(http.Request request) responder, {
  List<http.Request>? captured,
}) {
  final client = MockClient((request) async {
    captured?.add(request);
    return responder(request);
  });
  return BookingRepository(
    client: client,
    baseUrl: 'https://api.test',
    tokenGetter: () => 'tok-1',
  );
}

void main() {
  test(
    'posts the booking with the trip type, details, and bearer token',
    () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response('{"status":"received"}', 202),
        captured: captured,
      );

      await repo.submitRoundTrip(_booking);

      final request = captured.single;
      check(request.method).equals('POST');
      check(request.url.toString()).equals('https://api.test/me/bookings');
      check(request.headers['Authorization']).equals('Bearer tok-1');

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      check(body['tripType']).equals('roundTrip');
      final details = body['details'] as Map<String, dynamic>;
      check(details['hours']).equals(4);
      check(details['fare']).equals(440);
      check(details['scheduledAt']).equals('2026-07-20T09:15:00.000');
      check(
        (details['pickup'] as Map<String, dynamic>)['address'],
      ).equals('MG Road, Bengaluru');
    },
  );

  test('labels a one-way submission with its trip type', () async {
    final captured = <http.Request>[];
    final repo = _repo(
      (_) => http.Response('{"status":"received"}', 202),
      captured: captured,
    );

    await repo.submitOneWay(
      OneWayTrip(
        start: _pickup,
        destination: _pickup,
        scheduledAt: DateTime(2026, 7, 20, 9, 15),
        estimatedTravelTime: const Duration(hours: 1, minutes: 25),
        carType: CarType.suv,
        transmission: Transmission.manual,
      ),
    );

    final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
    check(body['tripType']).equals('oneWay');
    check(
      (body['details'] as Map<String, dynamic>)['estimatedTravelMinutes'],
    ).equals(85);
  });

  test('throws on a non-2xx response', () async {
    final repo = _repo((_) => http.Response('nope', 500));
    await check(
      repo.submitRoundTrip(_booking),
    ).throws<BookingSubmitException>();
  });

  test('throws when the server is unreachable', () async {
    final repo = _repo((_) => throw Exception('down'));
    await check(
      repo.submitRoundTrip(_booking),
    ).throws<BookingSubmitException>();
  });
}
