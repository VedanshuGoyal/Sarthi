import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/view_model/one_way_details_view_model.dart';

const _route = (
  start: PickupLocation(
    address: 'MG Road, Bengaluru',
    point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
  ),
  destination: PickupLocation(
    address: 'Kempegowda International Airport, Bengaluru',
    point: GeoPoint(latitude: 13.1986, longitude: 77.7066),
  ),
);

void main() {
  group('OneWayDetailsViewModel', () {
    test('defaults: pre-filled time, automatic gearbox, awaiting a car', () {
      final vm = OneWayDetailsViewModel(route: _route);
      check(vm.start.address).equals('MG Road, Bengaluru');
      check(vm.destination.address).contains('Airport');
      check(vm.scheduledAt).isNotNull();
      check(vm.transmission).equals(Transmission.automatic);
      check(vm.carType).isNull();
      check(vm.canContinue).isFalse();
      check(vm.draft).isNull();
    });

    test('picking a car type is enough to continue', () {
      final vm = OneWayDetailsViewModel(route: _route);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.selectCarType(CarType.suv);
      check(vm.canContinue).isTrue();
      vm.selectCarType(CarType.suv); // unchanged: no notify
      check(notifications).equals(1);

      final draft = vm.draft;
      check(draft).isNotNull();
      check(draft!.carType).equals(CarType.suv);
      check(draft.transmission).equals(Transmission.automatic);
      check(draft.start).equals(_route.start);
      check(draft.destination).equals(_route.destination);
      check(draft.scheduledAt).equals(vm.scheduledAt);
    });

    test('changing the schedule notifies and lands in the draft', () {
      final vm = OneWayDetailsViewModel(route: _route)
        ..selectCarType(CarType.sedan);
      var notifications = 0;
      vm.addListener(() => notifications++);

      final when = DateTime(2026, 7, 30, 9, 30);
      vm.setScheduledAt(when);
      check(vm.scheduledAt).equals(when);
      vm.setScheduledAt(when); // unchanged: no notify
      check(notifications).equals(1);

      check(vm.draft!.scheduledAt).equals(when);
    });

    test('switching the transmission notifies once and lands in the draft', () {
      final vm = OneWayDetailsViewModel(route: _route)
        ..selectCarType(CarType.sedan);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.selectTransmission(Transmission.manual);
      check(vm.transmission).equals(Transmission.manual);
      vm.selectTransmission(Transmission.manual); // unchanged: no notify
      check(notifications).equals(1);

      check(vm.draft!.transmission).equals(Transmission.manual);
    });

    test('honours seeded initial state', () {
      final vm = OneWayDetailsViewModel(
        route: _route,
        initialScheduledAt: DateTime(2026, 7, 20, 9, 30),
        initialCarType: CarType.luxury,
        initialTransmission: Transmission.manual,
      );
      check(vm.canContinue).isTrue();
      check(vm.scheduledAt).equals(DateTime(2026, 7, 20, 9, 30));
      check(vm.carType).equals(CarType.luxury);
      check(vm.transmission).equals(Transmission.manual);
    });
  });
}
