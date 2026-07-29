import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/view_model/multi_stop_planner_view_model.dart';

const _start = PickupLocation(
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
);

const _pharmacy = PickupLocation(
  address: 'Apollo Pharmacy, Lajpat Nagar',
  point: GeoPoint(latitude: 28.5677, longitude: 77.2433),
);

const _office = PickupLocation(
  address: 'Passport Seva Kendra, Bhikaji Cama Place, New Delhi',
  point: GeoPoint(latitude: 28.5679, longitude: 77.1859),
);

final _nineAm = DateTime(2026, 7, 18, 9);

/// A planner seeded with a fixed start time and no stops filled in.
MultiStopPlannerViewModel _vm({List<StopDraft>? stops}) =>
    MultiStopPlannerViewModel(
      start: _start,
      initialScheduledAt: _nineAm,
      initialStops: stops,
    );

/// Fills stop [id] completely: place, task, and a leave-by [at].
void _complete(
  MultiStopPlannerViewModel vm,
  int id,
  DateTime at, {
  PickupLocation location = _pharmacy,
}) {
  vm
    ..setStopLocation(id, location)
    ..setStopTask(id, 'Run the errand')
    ..setStopDepartBy(id, at);
}

void main() {
  group('MultiStopPlannerViewModel', () {
    test('defaults: one blank stop, pre-filled start, not confirmable', () {
      final vm = _vm();
      check(vm.scheduledAt).equals(_nineAm);
      check(vm.stops.length).equals(1);
      check(vm.stops.single.isComplete).isFalse();
      check(vm.canRemoveStop).isFalse();
      check(vm.canAddStop).isTrue();
      check(vm.canConfirm).isFalse();
      check(vm.trip).isNull();
    });

    test('stops can be added up to the cap and removed down to one', () {
      final vm = _vm();
      for (var i = 1; i < MultiStopPlannerViewModel.maxStops; i++) {
        vm.addStop();
      }
      check(vm.stops.length).equals(MultiStopPlannerViewModel.maxStops);
      check(vm.canAddStop).isFalse();
      vm.addStop(); // over the cap: no-op
      check(vm.stops.length).equals(MultiStopPlannerViewModel.maxStops);

      // Ids are distinct so drafts keep their identity.
      check(
        vm.stops.map((s) => s.id).toSet().length,
      ).equals(MultiStopPlannerViewModel.maxStops);

      while (vm.canRemoveStop) {
        vm.removeStop(vm.stops.last.id);
      }
      check(vm.stops.length).equals(1);
      final lastId = vm.stops.single.id;
      vm.removeStop(lastId); // the last stop can't be removed
      check(vm.stops.length).equals(1);
      check(vm.stops.single.id).equals(lastId);
    });

    test('reordering swaps neighbours and is a no-op at the edges', () {
      final vm = _vm();
      vm.addStop();
      vm.addStop();
      final ids = vm.stops.map((s) => s.id).toList();

      vm.moveStopUp(ids[0]); // already first: no-op
      check(vm.stops.map((s) => s.id).toList()).deepEquals(ids);

      vm.moveStopDown(ids[1]);
      check(
        vm.stops.map((s) => s.id).toList(),
      ).deepEquals([ids[0], ids[2], ids[1]]);

      vm.moveStopUp(ids[2]);
      check(
        vm.stops.map((s) => s.id).toList(),
      ).deepEquals([ids[2], ids[0], ids[1]]);
    });

    test('edits land on the right stop and notify only on change', () {
      final vm = _vm();
      vm.addStop();
      final first = vm.stops[0].id;
      final second = vm.stops[1].id;

      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.setStopTask(first, 'Collect the parcel');
      vm.setStopLocation(second, _office);
      check(vm.stops[0].task).equals('Collect the parcel');
      check(vm.stops[0].location).isNull();
      check(vm.stops[1].location).equals(_office);
      check(notifications).equals(2);

      vm.setStopTask(first, 'Collect the parcel'); // unchanged: no notify
      vm.setStopTask(999, 'Ghost stop'); // unknown id: ignored
      check(notifications).equals(2);
    });

    test('a whole day must run forward: leave-by times in visiting order', () {
      final vm = _vm();
      vm.addStop();
      final first = vm.stops[0].id;
      final second = vm.stops[1].id;

      // Stop 1 leaving before the trip even starts is flagged against the start.
      vm.setStopDepartBy(first, DateTime(2026, 7, 18, 8));
      check(
        vm.timeErrorFor(first),
      ).equals('Leave-by must be after the start time.');

      // Fixed: 10:30 works, and stop 2 must then come after stop 1.
      vm.setStopDepartBy(first, DateTime(2026, 7, 18, 10, 30));
      check(vm.timeErrorFor(first)).isNull();

      vm.setStopDepartBy(second, DateTime(2026, 7, 18, 10, 30));
      check(vm.timeErrorFor(second)).equals('Leave-by must be after stop 1.');

      vm.setStopDepartBy(second, DateTime(2026, 7, 18, 12));
      check(vm.timeErrorFor(second)).isNull();

      // Pushing the start past stop 1's deadline re-flags stop 1.
      vm.setScheduledAt(DateTime(2026, 7, 18, 11));
      check(vm.timeErrorFor(first)).isNotNull();
    });

    test(
      'confirm unlocks only when every stop is fully written and ordered',
      () {
        final vm = _vm();
        vm.addStop();
        final first = vm.stops[0].id;
        final second = vm.stops[1].id;

        _complete(vm, first, DateTime(2026, 7, 18, 10, 30));
        check(vm.canConfirm).isFalse(); // stop 2 still blank

        _complete(vm, second, DateTime(2026, 7, 18, 10), location: _office);
        check(vm.canConfirm).isFalse(); // stop 2 leaves before stop 1

        vm.setStopDepartBy(second, DateTime(2026, 7, 18, 12, 15));
        check(vm.canConfirm).isTrue();
        check(vm.endsAt).equals(DateTime(2026, 7, 18, 12, 15));
      },
    );

    test('a blank task or whitespace-only task keeps the stop incomplete', () {
      final vm = _vm();
      final id = vm.stops.single.id;
      vm.setStopLocation(id, _pharmacy);
      vm.setStopDepartBy(id, DateTime(2026, 7, 18, 10));
      check(vm.canConfirm).isFalse();

      vm.setStopTask(id, '   ');
      check(vm.canConfirm).isFalse();

      vm.setStopTask(id, 'Pick up the keys');
      check(vm.canConfirm).isTrue();
    });

    test('the assembled trip mirrors the plan, with tasks trimmed', () {
      final vm = _vm();
      vm.addStop();
      final first = vm.stops[0].id;
      final second = vm.stops[1].id;
      _complete(vm, first, DateTime(2026, 7, 18, 10, 30));
      _complete(vm, second, DateTime(2026, 7, 18, 12, 15), location: _office);
      vm.setStopTask(second, '  Drop the forms at counter 4  ');

      final trip = vm.trip;
      check(trip).isNotNull();
      check(trip!.start).equals(_start);
      check(trip.scheduledAt).equals(_nineAm);
      check(trip.stops.length).equals(2);
      check(trip.stops[0].location).equals(_pharmacy);
      check(trip.stops[1].task).equals('Drop the forms at counter 4');
      check(trip.endsAt).equals(DateTime(2026, 7, 18, 12, 15));

      final json = trip.toJson();
      check(json['scheduledAt']).equals('2026-07-18T09:00:00.000');
      check((json['stops'] as List).length).equals(2);
    });

    test('honours seeded initial stops and keeps new ids distinct', () {
      final vm = _vm(
        stops: [
          StopDraft(
            id: 3,
            location: _pharmacy,
            task: 'Collect the refill',
            departBy: DateTime(2026, 7, 18, 10),
          ),
        ],
      );
      check(vm.canConfirm).isTrue();
      vm.addStop();
      check(vm.stops[1].id).equals(4); // continues past the seeded id
    });
  });
}
