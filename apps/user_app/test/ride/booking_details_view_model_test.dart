import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/view_model/booking_details_view_model.dart';

const _pickup = PickupLocation(
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
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

const _luxury = Car(
  id: 'c3',
  registration: 'DL53LX9000',
  type: CarType.luxury,
  transmission: Transmission.automatic,
);

void main() {
  group('BookingDetailsViewModel', () {
    test('defaults: 2 hours, pre-filled time, awaiting a car', () {
      final vm = BookingDetailsViewModel(pickup: _pickup);
      check(vm.hours).equals(2);
      check(vm.car).isNull();
      // The start time is pre-filled, so only the car is still needed.
      check(vm.scheduledAt).isNotNull();
      check(vm.canConfirm).isFalse();
      check(vm.booking).isNull();
    });

    test('defaultScheduledAt is one hour out, rounded to the nearest 15 min', () {
      // 10:07 → +1h = 11:07 → nearest quarter = 11:00.
      check(
        BookingDetailsViewModel.defaultScheduledAt(
          DateTime(2026, 7, 16, 10, 7),
        ),
      ).equals(DateTime(2026, 7, 16, 11, 0));
      // 10:08 → +1h = 11:08 → nearest quarter = 11:15.
      check(
        BookingDetailsViewModel.defaultScheduledAt(
          DateTime(2026, 7, 16, 10, 8),
        ),
      ).equals(DateTime(2026, 7, 16, 11, 15));
      // 23:53 → +1h = 00:53 next day → nearest quarter = 01:00, seconds dropped.
      check(
        BookingDetailsViewModel.defaultScheduledAt(
          DateTime(2026, 7, 16, 23, 53, 40),
        ),
      ).equals(DateTime(2026, 7, 17, 1, 0));
    });

    test('hours clamp to the allowed range and notify only on change', () {
      final vm = BookingDetailsViewModel(pickup: _pickup);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.decrementHours(); // 2 -> 1
      check(vm.hours).equals(1);
      check(vm.canDecrementHours).isFalse();

      vm.decrementHours(); // already at min: no-op, no notification
      check(vm.hours).equals(1);
      check(notifications).equals(1);

      vm.setHours(999); // clamps to max
      check(vm.hours).equals(BookingDetailsViewModel.maxHours);
      check(vm.canIncrementHours).isFalse();
    });

    test('picking a car is enough to confirm (time is pre-filled)', () {
      final vm = BookingDetailsViewModel(pickup: _pickup);
      check(vm.canConfirm).isFalse();

      vm.selectCar(_suv);
      check(vm.canConfirm).isTrue();

      final booking = vm.booking;
      check(booking).isNotNull();
      check(booking!.car).equals(_suv);
      check(booking.hours).equals(2);
      check(booking.scheduledAt).equals(vm.scheduledAt);
      check(booking.pickup.address).equals('Connaught Place, New Delhi');
    });

    // A fixed midday start keeps these fares free of the after-10pm surcharge.
    final noon = DateTime(2026, 7, 18, 12);

    test(
      'fare tracks the hours at the standard rate until a car is chosen',
      () {
        final vm = BookingDetailsViewModel(
          pickup: _pickup,
          initialScheduledAt: noon,
        );
        vm.setHours(1);
        check(vm.fare).equals(139);
        vm.setHours(2);
        check(vm.fare).equals(240);
        vm.setHours(3); // +100 from the third hour on
        check(vm.fare).equals(340);
        vm.setHours(5);
        check(vm.fare).equals(540);
      },
    );

    test(
      'choosing a luxury car re-prices at the premium rate and quotes it',
      () {
        final vm = BookingDetailsViewModel(
          pickup: _pickup,
          initialScheduledAt: noon,
        );
        vm.setHours(3);
        check(vm.fare).equals(340); // standard preview

        vm.selectCar(_luxury);
        check(vm.fare).equals(440); // 330 + 110

        // A non-luxury pick falls back to the standard rate.
        vm.selectCar(_sedan);
        check(vm.fare).equals(340);

        // The confirmed booking carries the quoted fare.
        check(vm.booking!.fare).equals(340);
      },
    );

    test('a ride running past 10pm adds the flat + per-night-hour surcharge', () {
      // Starts 8pm for 3h → finishes 11pm: 1 hour after 10pm.
      final vm = BookingDetailsViewModel(
        pickup: _pickup,
        initialHours: 3,
        initialScheduledAt: DateTime(2026, 7, 18, 20),
      );
      check(vm.baseFare).equals(340);
      check(vm.nightSurcharge).equals(74); // 50 + 24×1
      check(vm.fare).equals(414);

      // A later start drives more night hours: 11pm for 2h → 1am = 2 night hours.
      vm.setHours(2);
      vm.setScheduledAt(DateTime(2026, 7, 18, 23));
      check(vm.baseFare).equals(240);
      check(vm.nightSurcharge).equals(98); // 50 + 24×2
      check(vm.fare).equals(338);
    });

    test('a ride finishing by 10pm carries no night surcharge', () {
      final vm = BookingDetailsViewModel(
        pickup: _pickup,
        initialHours: 2,
        initialScheduledAt: DateTime(2026, 7, 18, 20), // 8pm–10pm exactly
      );
      check(vm.nightSurcharge).equals(0);
      check(vm.fare).equals(240);
    });

    test('honours seeded initial state', () {
      final vm = BookingDetailsViewModel(
        pickup: _pickup,
        initialHours: 6,
        initialScheduledAt: DateTime(2026, 7, 18, 9, 30),
        initialCar: _luxury,
      );
      check(vm.canConfirm).isTrue();
      check(vm.hours).equals(6);
      check(vm.car).equals(_luxury);
    });
  });
}
