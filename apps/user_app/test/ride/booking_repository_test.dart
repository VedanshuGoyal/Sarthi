import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/round_trip_booking.dart';
import 'package:user_app/features/ride/domain/transmission.dart';

import '../support/fake_booking_server.dart';

const _pickup = PickupLocation(
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
  placeId: 'p1',
);

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.automatic,
);

final _booking = RoundTripBooking(
  pickup: _pickup,
  hours: 4,
  scheduledAt: DateTime(2026, 7, 20, 9, 15),
  car: _sedan,
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

/// The [BookingActionException] [action] fails with.
Future<BookingActionException> _failure(Future<Object?> action) async {
  try {
    await action;
  } on BookingActionException catch (e) {
    return e;
  }
  throw TestFailure('expected a BookingActionException');
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
      ).equals('Connaught Place, New Delhi');
      final car = details['car'] as Map<String, dynamic>;
      check(car['registration']).equals('DL01AB1234');
      check(car['carType']).equals('sedan');
      check(car['transmission']).equals('automatic');
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
        car: _sedan,
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

  group('booking actions', () {
    test('cancel posts the reason and returns the cancelled booking', () async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      final booking = await server.repository().cancel(
        'b1',
        reason: 'Plans changed',
      );

      final request = server.requests.single;
      check(request.method).equals('POST');
      check(request.url.path).equals('/me/bookings/b1/cancel');
      check(request.headers['Authorization']).equals('Bearer tok');
      check(
        jsonDecode(request.body) as Map,
      ).deepEquals({'reason': 'Plans changed'});
      check(booking.status).equals(BookingStatus.cancelled);
      check(booking.cancelReason).equals('Plans changed');
      check(booking.startOtp).isNull();
    });

    test('cancel without a reason sends an empty body', () async {
      final server = FakeBookingServer([bookingJson()]);
      await server.repository().cancel('b1');
      check(jsonDecode(server.requests.single.body) as Map).isEmpty();
    });

    test('rate posts the stars and note and returns myRating', () async {
      final server = FakeBookingServer([bookingJson(status: 'completed')]);
      final booking = await server.repository().rate(
        'b1',
        4,
        note: ' On time ',
      );

      final request = server.requests.single;
      check(request.url.path).equals('/me/bookings/b1/rating');
      check(
        jsonDecode(request.body) as Map,
      ).deepEquals({'stars': 4, 'note': 'On time'});
      check(booking.myRating!.stars).equals(4);
      check(booking.myRating!.note).equals('On time');
    });

    test('driverLocation reads a fix, or null when there is none', () async {
      final server = FakeBookingServer([bookingJson(status: 'arrived')])
        ..location = {
          'lat': 28.61,
          'lng': 77.21,
          'heading': 135.0,
          'updatedAt': '2030-10-26T04:59:50Z',
        };
      final repo = server.repository();

      final fix = (await repo.driverLocation('b1'))!;
      check(server.requests.single.method).equals('GET');
      check(
        server.requests.single.url.path,
      ).equals('/me/bookings/b1/driver-location');
      check(
        fix.point,
      ).equals(const GeoPoint(latitude: 28.61, longitude: 77.21));
      check(fix.heading).equals(135.0);

      server.location = null;
      check(await repo.driverLocation('b1')).isNull();
    });

    test('errors carry the backend code', () async {
      final server = FakeBookingServer([bookingJson(status: 'completed')]);
      final repo = server.repository();

      check(
        (await _failure(repo.cancel('nope'))).code,
      ).equals(BookingErrorCode.notFound);

      server.actionError = (409, 'booking_state');
      final refused = await _failure(repo.cancel('b1'));
      check(refused.code).equals(BookingErrorCode.wrongState);
      check(refused.statusCode).equals(409);
      check(refused.message).equals('Refused by test.');

      server.actionError = (400, 'invalid_rating');
      check(
        (await _failure(repo.rate('b1', 9))).code,
      ).equals(BookingErrorCode.invalidRating);

      server.locationError = (409, 'not_tracking');
      check(
        (await _failure(repo.driverLocation('b1'))).code,
      ).equals(BookingErrorCode.notTracking);
    });

    test('an unreachable server is an action error too', () async {
      final repo = _repo((_) => throw Exception('down'));
      final error = await _failure(repo.cancel('b1'));
      check(error.statusCode).isNull();
      check(error.code).equals(BookingErrorCode.other);
    });
  });
}
