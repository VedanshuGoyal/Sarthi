import 'package:checks/checks.dart';
import 'package:driver_app/features/rides/data/rides_repository.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/view/ride_format.dart';
import 'package:driver_app/features/rides/view_model/duty_view_model.dart';
import 'package:driver_app/features/rides/view_model/my_rides_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('DutyViewModel', () {
    late FakeRidesRepository repo;
    late List<Ride> handedOver;
    late DutyViewModel vm;

    setUp(() {
      repo = FakeRidesRepository()..openRides = [ride(id: 'a'), ride(id: 'b')];
      handedOver = [];
      vm = DutyViewModel(
        repository: repo,
        location: const FakeLocationService(),
        onAccepted: handedOver.add,
        pollEvery: const Duration(hours: 1),
      );
    });
    tearDown(() => vm.dispose());

    test('going online reports duty and loads nearby requests', () async {
      await vm.setOnline(true);

      check(vm.isOnline).isTrue();
      check(vm.hasPosition).isTrue();
      check(repo.duty).deepEquals([true]);
      check(vm.requests.map((r) => r.id)).deepEquals(['a', 'b']);
    });

    test('going offline clears the feed', () async {
      await vm.setOnline(true);
      await vm.setOnline(false);

      check(vm.isOnline).isFalse();
      check(vm.requests).isEmpty();
      check(repo.duty).deepEquals([true, false]);
    });

    test('accepting hands the ride over and drops it from the feed', () async {
      await vm.setOnline(true);
      final error = await vm.accept(vm.requests.first);

      check(error).isNull();
      check(vm.requests.map((r) => r.id)).deepEquals(['b']);
      check(handedOver.single.status).equals(RideStatus.accepted);
    });

    test('losing the race drops the ride with a friendly message', () async {
      repo.failures[RideAction.accept] = const RidesException(
        'This ride is no longer available.',
        code: 'ride_unavailable',
      );
      await vm.setOnline(true);
      final error = await vm.accept(vm.requests.first);

      check(error).equals('Another driver took this ride.');
      check(vm.requests.map((r) => r.id)).deepEquals(['b']);
      check(handedOver).isEmpty();
    });

    test('a clash keeps the ride and passes the reason on', () async {
      repo.failures[RideAction.accept] = const RidesException(
        "This ride overlaps one you've already accepted.",
        code: 'ride_clash',
      );
      await vm.setOnline(true);
      final error = await vm.accept(vm.requests.first);

      check(error).isNotNull().contains('overlaps');
      check(vm.requests).length.equals(2);
    });
  });

  group('MyRidesViewModel', () {
    test('splits rides into upcoming, ongoing and completed', () async {
      final repo = FakeRidesRepository()
        ..mine = [
          ride(id: 'up', status: 'accepted'),
          ride(id: 'at', status: 'arrived'),
          ride(id: 'on', status: 'in_progress'),
          ride(id: 'done', status: 'completed'),
        ];
      final vm = MyRidesViewModel(repository: repo);
      await vm.load();

      check(vm.upcoming.map((r) => r.id)).deepEquals(['up']);
      check(vm.ongoing.map((r) => r.id).toSet()).deepEquals({'at', 'on'});
      check(vm.completed.map((r) => r.id)).deepEquals(['done']);
      // Something underway beats the next upcoming ride.
      check(vm.current!.status.isActive).isTrue();
      check(vm.current!.status).not((s) => s.equals(RideStatus.accepted));
    });

    test('steps a ride forward and refreshes earnings on completion', () async {
      final repo = FakeRidesRepository()
        ..mine = [ride(id: 'r', status: 'accepted')];
      var earningsRefreshed = 0;
      final vm = MyRidesViewModel(
        repository: repo,
        onCompleted: () => earningsRefreshed++,
      );
      await vm.load();

      for (final action in [
        RideAction.arrive,
        RideAction.start,
        RideAction.complete,
      ]) {
        check(await vm.act(vm.byId('r')!, action)).isNull();
      }
      check(vm.byId('r')!.status).equals(RideStatus.completed);
      check(vm.completed).length.equals(1);
      check(earningsRefreshed).equals(1);
    });

    test('starting sends the code and surfaces a wrong one', () async {
      final repo = FakeRidesRepository()
        ..mine = [ride(id: 'r', status: 'arrived')];
      final vm = MyRidesViewModel(repository: repo);
      await vm.load();

      repo.failures[RideAction.start] = const RidesException(
        "That code doesn't match.",
        code: 'start_otp_incorrect',
      );
      check(
        await vm.act(vm.byId('r')!, RideAction.start, otp: '1234'),
      ).equals("That code doesn't match.");
      check(repo.lastOtp).equals('1234');
      check(vm.byId('r')!.status).equals(RideStatus.arrived);

      repo.failures.clear();
      check(
        await vm.act(vm.byId('r')!, RideAction.start, otp: '4821'),
      ).isNull();
      check(repo.lastOtp).equals('4821');
      check(vm.byId('r')!.status).equals(RideStatus.inProgress);
    });

    test('releasing removes the ride', () async {
      final repo = FakeRidesRepository()
        ..mine = [ride(id: 'r', status: 'accepted')];
      final vm = MyRidesViewModel(repository: repo);
      await vm.load();

      check(await vm.act(vm.byId('r')!, RideAction.release)).isNull();
      check(vm.byId('r')).isNull();
    });
  });

  group('RideFormat', () {
    test('groups rupees the Indian way', () {
      check(RideFormat.rupees(240)).equals('₹240');
      check(RideFormat.rupees(1240)).equals('₹1,240');
      check(RideFormat.rupees(123456)).equals('₹1,23,456');
      check(RideFormat.rupees(12345678)).equals('₹1,23,45,678');
    });

    test('names nearby days', () {
      final now = DateTime(2026, 10, 25, 10);
      check(
        RideFormat.day(DateTime(2026, 10, 25, 22), now: now),
      ).equals('Today');
      check(
        RideFormat.day(DateTime(2026, 10, 26, 1), now: now),
      ).equals('Tomorrow');
      check(
        RideFormat.day(DateTime(2026, 10, 28, 9), now: now),
      ).equals('Wed, 28 Oct');
      check(RideFormat.time(DateTime(2026, 10, 25, 0, 5))).equals('12:05 AM');
      check(RideFormat.time(DateTime(2026, 10, 25, 13, 30))).equals('1:30 PM');
    });

    test('reads durations and distances', () {
      check(RideFormat.duration(const Duration(minutes: 45))).equals('45 min');
      check(
        RideFormat.duration(const Duration(minutes: 105)),
      ).equals('1 h 45 min');
      check(RideFormat.distance(720)).equals('700 m');
      check(RideFormat.distance(7740)).equals('7.7 km');
      check(RideFormat.phone('+919800012345')).equals('+91 98000 12345');
    });
  });
}
