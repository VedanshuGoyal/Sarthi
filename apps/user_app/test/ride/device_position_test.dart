import 'dart:async';

import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:user_app/features/ride/data/location_repository.dart'
    as repo
    show LocationException;
import 'package:user_app/features/ride/data/location_repository.dart'
    hide LocationException, LocationServiceDisabledException;
import 'package:user_app/features/ride/domain/geo_point.dart';

/// A GPS that has permission but never gets a fix (indoors), unless
/// [currentFix] is set; [lastKnown] is what the OS remembers.
class _FakeGeolocator extends GeolocatorPlatform {
  Position? lastKnown;
  Future<Position> Function()? currentFix;
  Object? permissionError;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async {
    if (permissionError case final e?) throw e;
    return LocationPermission.whileInUse;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      currentFix?.call() ?? Completer<Position>().future;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => lastKnown;
}

Position _position(double lat, double lng, DateTime at) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: at,
  accuracy: 20,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late GeolocatorPlatform original;
  late _FakeGeolocator gps;

  setUp(() {
    original = GeolocatorPlatform.instance;
    gps = _FakeGeolocator();
    GeolocatorPlatform.instance = gps;
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  // The real device fetcher: no positionFetcher injected.
  LocationRepository repository() =>
      LocationRepository(tokenProvider: () async => 'token');

  /// Reads the device position, letting [wait] of fake time pass.
  (GeoPoint?, Object?) readPoint(Duration wait) {
    GeoPoint? point;
    Object? error;
    fakeAsync((async) {
      repository().currentPoint().then<void>(
        (p) => point = p,
        onError: (Object e) => error = e,
      );
      async.elapse(wait);
    });
    return (point, error);
  }

  test('a fix that never comes fails instead of hanging', () {
    final (point, error) = readPoint(
      LocationRepository.fixTimeout + const Duration(seconds: 1),
    );

    check(point).isNull();
    check(error).isA<repo.LocationException>();
  });

  test('a recent last-known fix stands in when GPS is slow', () {
    gps.lastKnown = _position(28.6, 77.2, DateTime.now());

    final (point, error) = readPoint(
      LocationRepository.fixTimeout + const Duration(seconds: 1),
    );

    check(error).isNull();
    check(point).equals(const GeoPoint(latitude: 28.6, longitude: 77.2));
  });

  test('a stale last-known fix is not used as the pickup', () {
    gps.lastKnown = _position(
      28.6,
      77.2,
      DateTime.now().subtract(const Duration(hours: 3)),
    );

    final (point, error) = readPoint(
      LocationRepository.fixTimeout + const Duration(seconds: 1),
    );

    check(point).isNull();
    check(error).isA<repo.LocationException>();
  });

  test('a plugin error comes out as a LocationException', () {
    gps.permissionError = const PermissionRequestInProgressException(
      'A request for location permissions is already running.',
    );

    final (point, error) = readPoint(Duration.zero);

    check(point).isNull();
    check(error).isA<repo.LocationException>();
  });

  test('a fix in time is used as is', () {
    gps.currentFix = () async => _position(28.5, 77.1, DateTime.now());

    final (point, error) = readPoint(Duration.zero);

    check(error).isNull();
    check(point).equals(const GeoPoint(latitude: 28.5, longitude: 77.1));
  });
}
