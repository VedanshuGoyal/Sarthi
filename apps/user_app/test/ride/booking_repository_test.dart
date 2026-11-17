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
      // An instant, not a wall time the server must guess the zone of.
      check(
        details['scheduledAt'],
      ).equals(DateTime(2026, 7, 20, 9, 15).toUtc().toIso8601String());
      check(details['scheduledAt'] as String).endsWith('Z');
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

  test("a refused booking carries the server's reason", () async {
    final repo = _repo(
      (_) => http.Response(
        jsonEncode({'error': 'pick a start time at least 45 minutes from now'}),
        400,
      ),
    );
    await check(repo.submitRoundTrip(_booking)).throws<BookingSubmitException>(
      (e) => e
          .has((e) => e.message, 'message')
          .equals('Pick a start time at least 45 minutes from now.'),
    );
  });

  group('idempotency key', () {
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('a key passed in is sent verbatim on every submit', () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response('{"id":"b1","status":"received"}', 202),
        captured: captured,
      );
      await repo.submitRoundTrip(_booking, idempotencyKey: 'attempt-1');
      await repo.submitRoundTrip(_booking, idempotencyKey: 'attempt-1');
      check(
        captured.map((r) => r.headers['Idempotency-Key']),
      ).deepEquals(['attempt-1', 'attempt-1']);
    });

    test('without one, each submit gets a fresh UUID v4', () async {
      final captured = <http.Request>[];
      final repo = _repo(
        (_) => http.Response('{"id":"b1","status":"received"}', 202),
        captured: captured,
      );
      await repo.submitRoundTrip(_booking);
      await repo.submitRoundTrip(_booking);
      final keys = [for (final r in captured) r.headers['Idempotency-Key']!];
      for (final key in keys) {
        check(key).matchesPattern(uuidV4);
      }
      check(keys.first).not((k) => k.equals(keys.last));
    });

    test('newIdempotencyKey is a UUID v4', () {
      for (var i = 0; i < 50; i++) {
        check(newIdempotencyKey()).matchesPattern(uuidV4);
      }
    });

    test('a repeat the server recognised is a success', () async {
      final repo = _repo(
        (_) => http.Response(
          '{"id":"b1","status":"received","duplicate":true}',
          200,
        ),
      );
      await repo.submitRoundTrip(_booking, idempotencyKey: 'attempt-1');
    });
  });

  test('a booking refused for an unpaid ride names that ride', () async {
    final repo = _repo(
      (_) => http.Response(
        jsonEncode({
          'error': 'pay for your last ride before booking another',
          'code': 'payment_due',
          'bookingId': 'unpaid-1',
        }),
        409,
      ),
    );
    await check(repo.submitRoundTrip(_booking)).throws<BookingSubmitException>(
      (e) => e
        ..has((e) => e.isPaymentDue, 'isPaymentDue').isTrue()
        ..has((e) => e.code, 'code').equals('payment_due')
        ..has((e) => e.bookingId, 'bookingId').equals('unpaid-1')
        ..has(
          (e) => e.message,
          'message',
        ).equals('Pay for your last ride before booking another.'),
    );
  });

  test('a payment_due refusal without a ride id is a plain refusal', () async {
    final repo = _repo(
      (_) => http.Response(
        jsonEncode({
          'error': 'pay for your last ride before booking another',
          'code': 'payment_due',
        }),
        409,
      ),
    );
    await check(repo.submitRoundTrip(_booking)).throws<BookingSubmitException>(
      (e) => e
        ..has((e) => e.isPaymentDue, 'isPaymentDue').isFalse()
        ..has(
          (e) => e.message,
          'message',
        ).equals('Pay for your last ride before booking another.'),
    );
  });

  test('an unreadable bookings list is a load failure', () async {
    for (final body in ['<html>ok</html>', '{"bookings": "nope"}', '[]']) {
      final repo = _repo((_) => http.Response(body, 200));
      await check(repo.myBookings()).throws<BookingSubmitException>();
    }
    final empty = _repo((_) => http.Response('{}', 200));
    check(await empty.myBookings()).isEmpty();
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
      ).deepEquals({'reason': 'Plans changed', 'acceptFeePaise': 0});
      check(booking.status).equals(BookingStatus.cancelled);
      check(booking.cancelReason).equals('Plans changed');
      check(booking.startOtp).isNull();
    });

    test('cancel without a reason still says what fee it agreed to', () async {
      final server = FakeBookingServer([bookingJson()]);
      await server.repository().cancel('b1');
      check(
        jsonDecode(server.requests.single.body) as Map,
      ).deepEquals({'acceptFeePaise': 0});
    });

    test('cancelling at the pickup for more than agreed is refused with the '
        'fee', () async {
      final server = FakeBookingServer([
        bookingJson(status: 'arrived', cancellationFeePaise: 5000),
      ]);
      final repo = server.repository();

      final refused = await _failure(
        repo.cancel('b1', reason: 'Plans changed'),
      );
      check(refused.code).equals(BookingErrorCode.cancellationFee);
      check(refused.statusCode).equals(409);
      check(refused.feePaise).equals(5000);
      check(server.bookings.single['status']).equals('arrived');

      final booking = await repo.cancel('b1', acceptFeePaise: 5000);
      check(
        jsonDecode(server.requests.last.body) as Map,
      ).deepEquals({'acceptFeePaise': 5000});
      check(booking.status).equals(BookingStatus.cancelled);
      check(booking.cancellationFeePaise).equals(5000);
      check(booking.paymentStatus).equals(RidePaymentStatus.due);
    });

    test('endTrip posts to /end and returns the trip charged for the time '
        'used', () async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      final booking = await server.repository().endTrip('b1');

      final request = server.requests.single;
      check(request.method).equals('POST');
      check(request.url.path).equals('/me/bookings/b1/end');
      check(request.headers['Authorization']).equals('Bearer tok');
      check(booking.status).equals(BookingStatus.completed);
      check(booking.farePaise).equals(24000);
      check(booking.bookedFarePaise).equals(64000);
      check(booking.paymentStatus).equals(RidePaymentStatus.due);
    });

    test('ending a trip that is not in progress is cannot_end', () async {
      final server = FakeBookingServer([bookingJson(status: 'arrived')]);
      final refused = await _failure(server.repository().endTrip('b1'));
      check(refused.code).equals(BookingErrorCode.cannotEnd);
      check(refused.statusCode).equals(409);
      check(refused.feePaise).isNull();
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
