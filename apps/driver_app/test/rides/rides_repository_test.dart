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

  test('decline answers with no ride', () async {
    final result = await repo(null, status: 204).act('r1', RideAction.decline);
    check(result).isNull();
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
}
