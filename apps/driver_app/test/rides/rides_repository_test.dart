import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/features/rides/data/rides_repository.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

void main() {
  RidesRepository repo(
    Object? body, {
    int status = 200,
    void Function(http.Request)? onRequest,
  }) {
    return RidesRepository(
      baseUrl: 'http://api',
      tokenGetter: () => 'tok',
      client: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(body == null ? '' : jsonEncode(body), status);
      }),
    );
  }

  test('requests sends the position and skips rides it cannot read', () async {
    late http.Request sent;
    final rides = await repo({
      'rides': [
        rideJson(),
        {'id': 'broken'},
      ],
    }, onRequest: (r) => sent = r).requests(lat: 28.6, lng: 77.2);

    check(
      sent.url.toString(),
    ).equals('http://api/driver/rides/requests?lat=28.6&lng=77.2');
    check(sent.headers['Authorization']).equals('Bearer tok');
    check(rides).length.equals(1);
    final ride = rides.single;
    check(ride.kind).equals(TripKind.roundTrip);
    check(ride.status).equals(RideStatus.requested);
    check(ride.fareRupees).equals(340);
    check(ride.car!.transmissionLabel).equals('Automatic');
    check(ride.duration).equals(const Duration(hours: 3));
    check(ride.customer).isNull();
  });

  test('an unreadable 2xx body is a RidesException, not a raw error', () async {
    RidesRepository html() => RidesRepository(
      baseUrl: 'http://api',
      client: MockClient((_) async => http.Response('<html>ok</html>', 200)),
    );

    await check(html().myRides()).throws<RidesException>();
    await check(html().requests()).throws<RidesException>();
    await check(html().act('r1', RideAction.arrive)).throws<RidesException>();
    await check(html().earnings()).throws<RidesException>();
    await check(repo({'rides': 'nope'}).myRides()).throws<RidesException>();
  });

  test('act posts the action and returns the updated ride', () async {
    late http.Request sent;
    final updated = await repo({
      'ride': rideJson(status: 'accepted', withCustomer: true),
    }, onRequest: (r) => sent = r).act('r1', RideAction.accept);

    check(sent.method).equals('POST');
    check(sent.url.path).equals('/driver/rides/r1/accept');
    check(updated!.status).equals(RideStatus.accepted);
    check(updated.customer!.name).equals('Asha Kumari');
  });

  test('start sends the customer\'s code', () async {
    late http.Request sent;
    await repo({
      'ride': rideJson(status: 'in_progress', withCustomer: true),
    }, onRequest: (r) => sent = r).act('r1', RideAction.start, otp: '4821');
    check(sent.url.path).equals('/driver/rides/r1/start');
    check(
      jsonDecode(sent.body) as Map<String, dynamic>,
    ).deepEquals({'otp': '4821'});
  });

  test('decline answers with no ride', () async {
    final result = await repo(null, status: 204).act('r1', RideAction.decline);
    check(result).isNull();
  });

  test('rate sends stars and note, and reads back myRating', () async {
    late http.Request sent;
    final updated = await repo(
      {
        'ride': rideJson(
          status: 'completed',
          myRating: {'stars': 4, 'note': 'Great customer'},
        ),
      },
      onRequest: (r) => sent = r,
    ).act('r1', RideAction.rate, stars: 4, note: 'Great customer');

    check(sent.url.path).equals('/driver/rides/r1/rate');
    check(
      jsonDecode(sent.body) as Map<String, dynamic>,
    ).deepEquals({'stars': 4, 'note': 'Great customer'});
    check(updated!.myRating!.stars).equals(4);
  });

  test('rate omits note when none was given', () async {
    late http.Request sent;
    await repo({
      'ride': rideJson(status: 'completed'),
    }, onRequest: (r) => sent = r).act('r1', RideAction.rate, stars: 5);

    check(
      jsonDecode(sent.body) as Map<String, dynamic>,
    ).deepEquals({'stars': 5});
  });

  test('errors carry the backend code and a sentence-cased message', () async {
    await check(
      repo({
        'error': 'this ride is no longer available',
        'code': 'ride_unavailable',
      }, status: 409).act('r1', RideAction.accept),
    ).throws<RidesException>((failure) {
      failure.has((e) => e.code, 'code').equals('ride_unavailable');
      failure
          .has((e) => e.message, 'message')
          .equals('This ride is no longer available.');
    });
  });

  test('earnings parses every window', () async {
    final e = await repo({
      'today': {'farePaise': 34000, 'rides': 1},
      'week': {'farePaise': 58000, 'rides': 2},
      'month': {'farePaise': 58000, 'rides': 2},
      'total': {'farePaise': 99900, 'rides': 4},
    }).earnings();
    check(e.today.rupees).equals(340);
    check(e.week.rides).equals(2);
    check(e.total.rupees).equals(999);
    // An older server sends only the gross.
    check(e.today.netPaise).isNull();
    check(e.today.netRupees).isNull();
  });

  test('earnings reads the driver\'s net share beside the gross', () async {
    final e = await repo({
      'today': {'farePaise': 34000, 'rides': 1, 'netPaise': 29580},
      'week': {'farePaise': 58000, 'rides': 2, 'netPaise': 50460},
      'month': {'farePaise': 0, 'rides': 0, 'netPaise': 0},
      'total': {'farePaise': 99900, 'rides': 4},
    }).earnings();
    check(e.today.rupees).equals(340);
    check(e.today.netPaise).equals(29580);
    check(e.today.netRupees).equals(296);
    check(e.week.netRupees).equals(505);
    check(e.month.netPaise).equals(0);
    check(e.total.netPaise).isNull();
  });

  test('payouts lists the transfers and skips ones it cannot read', () async {
    late http.Request sent;
    final payouts = await repo({
      'payouts': [
        {
          'id': 'p2',
          'driverId': 'd1',
          'amountPaise': 13050,
          'rides': 2,
          'reference': 'UTR123',
          'createdAt': '2026-11-10T12:00:00Z',
        },
        {'id': 'broken'},
        {
          'id': 'p1',
          'amountPaise': 29580,
          'rides': 1,
          'createdAt': '2026-11-03T09:30:00Z',
        },
      ],
    }, onRequest: (r) => sent = r).payouts();

    check(sent.method).equals('GET');
    check(sent.url.path).equals('/driver/payouts');
    check(sent.headers['Authorization']).equals('Bearer tok');
    check(payouts.map((p) => p.id).toList()).deepEquals(['p2', 'p1']);
    final first = payouts.first;
    check(first.amountPaise).equals(13050);
    check(first.rupees).equals(131);
    check(first.rides).equals(2);
    check(first.reference).equals('UTR123');
    check(first.createdAt.toUtc()).equals(DateTime.utc(2026, 11, 10, 12));
    check(payouts.last.reference).equals('');
  });

  test('payouts on a server without the list is an empty list', () async {
    final payouts = await repo('404 page not found', status: 404).payouts();
    check(payouts).isEmpty();
  });

  test('payouts failures other than 404 are RidesExceptions', () async {
    await check(
      repo({'error': 'could not list payouts'}, status: 500).payouts(),
    ).throws<RidesException>(
      (e) => e.has((e) => e.statusCode, 'statusCode').equals(500),
    );
    await check(repo({'payouts': 'nope'}).payouts()).throws<RidesException>();
  });

  test('setDuty sends the switch and position', () async {
    late http.Request sent;
    await repo({
      'online': true,
    }, onRequest: (r) => sent = r).setDuty(online: true, lat: 1.5, lng: 2.5);
    check(sent.method).equals('PUT');
    check(
      jsonDecode(sent.body) as Map<String, dynamic>,
    ).deepEquals({'online': true, 'lat': 1.5, 'lng': 2.5});
  });

  test('shareLocation puts lat/lng and an optional heading', () async {
    late http.Request sent;
    await repo(
      null,
      status: 204,
      onRequest: (r) => sent = r,
    ).shareLocation(lat: 28.61, lng: 77.21, heading: 135.0);

    check(sent.method).equals('PUT');
    check(sent.url.path).equals('/driver/location');
    check(
      jsonDecode(sent.body) as Map<String, dynamic>,
    ).deepEquals({'lat': 28.61, 'lng': 77.21, 'heading': 135.0});
  });

  test('shareLocation omits heading when none was given', () async {
    late http.Request sent;
    await repo(
      null,
      status: 204,
      onRequest: (r) => sent = r,
    ).shareLocation(lat: 28.61, lng: 77.21);

    check(
      jsonDecode(sent.body) as Map<String, dynamic>,
    ).deepEquals({'lat': 28.61, 'lng': 77.21});
  });
}
