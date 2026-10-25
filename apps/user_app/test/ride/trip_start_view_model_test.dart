import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/service_area.dart';
import 'package:user_app/features/ride/view_model/trip_start_view_model.dart';

import '../support/fake_location_repository.dart';

const _here = PickupLocation(
  address: 'My street, New Delhi',
  point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
);

const _home = PickupLocation(
  address: 'Home, Saket',
  point: GeoPoint(latitude: 28.5245, longitude: 77.2066),
  placeId: 'r1',
);

/// A fresh fix a little way from [_here].
const _moved = PickupLocation(
  address: 'Next street, New Delhi',
  point: GeoPoint(latitude: 28.6150, longitude: 77.2100),
);

/// A repository whose GPS fix arrives only when the test completes it.
class _SlowGpsRepository extends FakeLocationRepository {
  final fix = Completer<PickupLocation>();

  @override
  Future<PickupLocation> currentLocation() => fix.future;
}

void main() {
  group('TripStartViewModel', () {
    test('fills the start from GPS', () async {
      final vm = TripStartViewModel(
        repository: FakeLocationRepository(current: _here),
      );
      final pending = vm.locate();
      check(vm.isLocating).isTrue();

      check(await pending).equals(_here);
      check(vm.start).equals(_here);
      check(vm.isCurrentLocation).isTrue();
      check(vm.isLocating).isFalse();
      check(vm.error).isNull();
    });

    test('leaves the start empty when GPS is refused', () async {
      final vm = TripStartViewModel(
        repository: FakeLocationRepository(
          currentError: const LocationPermissionException('Allow location'),
        ),
      );

      check(await vm.locate()).isNull();
      check(vm.start).isNull();
      check(vm.error).equals('Allow location');
    });

    test('ignores a fix outside the service area', () async {
      final vm = TripStartViewModel(
        repository: FakeLocationRepository(
          current: const PickupLocation(
            address: 'MG Road, Bengaluru',
            point: GeoPoint(latitude: 12.97, longitude: 77.6),
          ),
        ),
      );

      check(await vm.locate()).isNull();
      check(vm.start).isNull();
      check(vm.error).equals(ServiceArea.outsideMessage);
    });

    test('a manual pick wins over a GPS fix that lands later', () async {
      final repo = _SlowGpsRepository();
      final vm = TripStartViewModel(repository: repo);
      final pending = vm.locate();

      vm.setStart(_home);
      repo.fix.complete(_here);

      check(await pending).equals(_home);
      check(vm.start).equals(_home);
      check(vm.isCurrentLocation).isFalse();
    });

    test('concurrent callers share one fix', () async {
      final repo = _SlowGpsRepository();
      final vm = TripStartViewModel(repository: repo);
      final first = vm.locate();
      final second = vm.locate();

      repo.fix.complete(_here);

      check(await first).equals(_here);
      check(await second).equals(_here);
    });

    group('with a spot remembered from earlier', () {
      test('opens filled, without the locating state', () {
        final vm = TripStartViewModel(
          repository: FakeLocationRepository(lastKnown: _here, current: _moved),
        );
        check(vm.start).equals(_here);
        check(vm.isCurrentLocation).isTrue();
        check(vm.isLocating).isFalse();
      });

      test('a fresh fix replaces it quietly', () async {
        final repo = _SlowGpsRepository()..lastKnown = _here;
        final vm = TripStartViewModel(repository: repo);
        final pending = vm.locate();
        check(vm.isLocating).isFalse();
        check(vm.start).equals(_here);

        repo.fix.complete(_moved);
        check(await pending).equals(_moved);
        check(vm.start).equals(_moved);
      });

      test('a failed fix keeps the remembered spot', () async {
        final vm = TripStartViewModel(
          repository: FakeLocationRepository(
            lastKnown: _here,
            currentError: const LocationPermissionException('Allow location'),
          ),
        );
        check(await vm.locate()).equals(_here);
        check(vm.error).isNull();
      });

      test('a manual pick wins over the refresh', () async {
        final repo = _SlowGpsRepository()..lastKnown = _here;
        final vm = TripStartViewModel(repository: repo);
        final pending = vm.locate();

        vm.setStart(_home);
        repo.fix.complete(_moved);
        check(await pending).equals(_home);
        check(vm.start).equals(_home);
      });
    });
  });
}
