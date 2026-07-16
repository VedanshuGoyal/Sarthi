import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/view_model/map_pickup_view_model.dart';

import '../support/fake_location_repository.dart';

void main() {
  group('MapPickupViewModel', () {
    test('starts not ready and cannot confirm', () {
      final vm = MapPickupViewModel(repository: FakeLocationRepository());
      check(vm.isReady).isFalse();
      check(vm.canConfirm).isFalse();
    });

    test('init centres on the device fix and resolves its address', () async {
      final repo = FakeLocationRepository(
        currentPos: const GeoPoint(latitude: 12.97, longitude: 77.6),
        reverseResult: const PickupLocation(
          address: 'MG Road, Bengaluru',
          point: GeoPoint(latitude: 12.97, longitude: 77.6),
        ),
      );
      final vm = MapPickupViewModel(repository: repo);

      await vm.init();

      check(vm.isReady).isTrue();
      check(vm.initialCenter).equals(
        const GeoPoint(latitude: 12.97, longitude: 77.6),
      );
      check(vm.resolved?.address).equals('MG Road, Bengaluru');
      check(vm.canConfirm).isTrue();
    });

    test('init falls back to the default centre when GPS is refused', () async {
      final repo = FakeLocationRepository(
        currentError: const LocationPermissionException('nope'),
      );
      final vm = MapPickupViewModel(repository: repo);

      await vm.init();

      check(vm.isReady).isTrue();
      check(vm.initialCenter).equals(MapPickupViewModel.defaultCenter);
      // Fallback centre is not surfaced as an error — the user can still pan.
      check(vm.error).isNull();
    });

    test('panning drops the stale selection until the camera settles', () async {
      final repo = FakeLocationRepository();
      final vm = MapPickupViewModel(repository: repo)..init();
      await Future<void>.value();

      vm.onCameraMove(const GeoPoint(latitude: 1, longitude: 2));
      check(vm.isMoving).isTrue();
      check(vm.canConfirm).isFalse();

      await vm.onCameraIdle();
      check(vm.isMoving).isFalse();
      check(vm.center).equals(const GeoPoint(latitude: 1, longitude: 2));
      check(vm.resolved).isNotNull();
      check(vm.canConfirm).isTrue();
    });

    test('a later settle wins over an in-flight earlier resolve', () async {
      // The seq guard means only the newest settle writes results.
      final repo = FakeLocationRepository(
        reverseResult: const PickupLocation(
          address: 'Second',
          point: GeoPoint(latitude: 3, longitude: 4),
        ),
      );
      final vm = MapPickupViewModel(repository: repo);
      await vm.init();

      vm.onCameraMove(const GeoPoint(latitude: 3, longitude: 4));
      final first = vm.onCameraIdle();
      vm.onCameraMove(const GeoPoint(latitude: 3, longitude: 4));
      final second = vm.onCameraIdle();
      await Future.wait([first, second]);

      check(vm.resolved?.address).equals('Second');
      check(vm.isResolving).isFalse();
    });

    test('a failed resolve surfaces the error and blocks confirm', () async {
      final repo = FakeLocationRepository(
        reverseError: const LocationException('maps down'),
      );
      final vm = MapPickupViewModel(repository: repo);
      await vm.init();

      check(vm.error).equals('maps down');
      check(vm.resolved).isNull();
      check(vm.canConfirm).isFalse();
    });

    test('locateMe returns the current point for the camera', () async {
      final repo = FakeLocationRepository(
        currentPos: const GeoPoint(latitude: 9, longitude: 8),
      );
      final vm = MapPickupViewModel(repository: repo);

      final point = await vm.locateMe();
      check(point).equals(const GeoPoint(latitude: 9, longitude: 8));
    });

    test('locateMe surfaces the error when GPS is unavailable', () async {
      final repo = FakeLocationRepository(
        currentError: const LocationServiceDisabledException('off'),
      );
      final vm = MapPickupViewModel(repository: repo);

      final point = await vm.locateMe();
      check(point).isNull();
      check(vm.error).equals('off');
    });
  });
}
