import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/view_model/trip_selection_view_model.dart';

void main() {
  group('TripSelectionViewModel', () {
    test('starts with nothing selected', () {
      final vm = TripSelectionViewModel();
      check(vm.selectedType).isNull();
    });

    test('selecting a type records it and notifies once', () {
      final vm = TripSelectionViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.select(TripType.roundTrip);
      check(vm.selectedType).equals(TripType.roundTrip);
      check(notifications).equals(1);

      // Re-selecting the same type is a no-op — no extra notification.
      vm.select(TripType.roundTrip);
      check(notifications).equals(1);

      vm.select(TripType.multiStop);
      check(vm.selectedType).equals(TripType.multiStop);
      check(notifications).equals(2);
    });

    test('honours a pre-selected initial type', () {
      final vm = TripSelectionViewModel(initialType: TripType.multiStop);
      check(vm.selectedType).equals(TripType.multiStop);
    });
  });
}
