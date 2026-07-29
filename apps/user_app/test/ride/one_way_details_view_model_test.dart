import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/view_model/one_way_details_view_model.dart';

const _route = (
  start: PickupLocation(
    address: 'Connaught Place, New Delhi',
    point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
  ),
  destination: PickupLocation(
    address: 'Indira Gandhi International Airport, New Delhi',
    point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
  ),
);

const _suv = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.suv,
  transmission: Transmission.automatic,
);

const _sedan = Car(
  id: 'c2',
  registration: 'DL05MN0007',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

void main() {
  group('OneWayDetailsViewModel', () {
    test('defaults: pre-filled time, awaiting a car', () {
      final vm = OneWayDetailsViewModel(route: _route);
      check(vm.start.address).equals('Connaught Place, New Delhi');
      check(vm.destination.address).contains('Airport');
      check(vm.scheduledAt).isNotNull();
      check(vm.car).isNull();
      check(vm.canContinue).isFalse();
      check(vm.draft).isNull();
    });

    test('picking a car is enough to continue', () {
      final vm = OneWayDetailsViewModel(route: _route);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.selectCar(_suv);
      check(vm.canContinue).isTrue();
      vm.selectCar(_suv); // unchanged: no notify
      check(notifications).equals(1);

      final draft = vm.draft;
      check(draft).isNotNull();
      check(draft!.car).equals(_suv);
      check(draft.start).equals(_route.start);
      check(draft.destination).equals(_route.destination);
      check(draft.scheduledAt).equals(vm.scheduledAt);
    });

    test('changing the schedule notifies and lands in the draft', () {
      final vm = OneWayDetailsViewModel(route: _route)..selectCar(_sedan);
      var notifications = 0;
      vm.addListener(() => notifications++);

      final when = DateTime(2026, 7, 30, 9, 30);
      vm.setScheduledAt(when);
      check(vm.scheduledAt).equals(when);
      vm.setScheduledAt(when); // unchanged: no notify
      check(notifications).equals(1);

      check(vm.draft!.scheduledAt).equals(when);
    });

    test('switching the car notifies once and lands in the draft', () {
      final vm = OneWayDetailsViewModel(route: _route)..selectCar(_sedan);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.selectCar(_suv);
      check(vm.car).equals(_suv);
      vm.selectCar(_suv); // unchanged: no notify
      check(notifications).equals(1);

      check(vm.draft!.car).equals(_suv);
    });

    test('honours seeded initial state', () {
      final vm = OneWayDetailsViewModel(
        route: _route,
        initialScheduledAt: DateTime(2026, 7, 20, 9, 30),
        initialCar: _sedan,
      );
      check(vm.canContinue).isTrue();
      check(vm.scheduledAt).equals(DateTime(2026, 7, 20, 9, 30));
      check(vm.car).equals(_sedan);
    });
  });
}
