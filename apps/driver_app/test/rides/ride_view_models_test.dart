import 'dart:async';

import 'package:checks/checks.dart';
import 'package:driver_app/core/services/location_service.dart';
import 'package:driver_app/features/rides/data/rides_repository.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/view/ride_format.dart';
import 'package:driver_app/features/rides/view_model/duty_view_model.dart';
import 'package:driver_app/features/rides/view_model/earnings_view_model.dart';
import 'package:driver_app/features/rides/view_model/my_rides_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// A [FakeRidesRepository] whose ride list and earnings are read when asked
/// for but only answered once [gate] (if set) completes — a slow poll.
class _GatedRides extends FakeRidesRepository {
  Completer<void>? gate;

  @override
  Future<List<Ride>> myRides() async {
    final answer = List.of(mine);
    final wait = gate;
    if (wait != null) await wait.future;
    return answer;
  }

  @override
  Future<Earnings> earnings() async {
    final wait = gate;
    if (wait != null) await wait.future;
    return summary;
  }
}

/// A [FakeLocationService] whose fix waits on [gate] when it's set — GPS
/// taking its time.
class _GatedLocation extends FakeLocationService {
  Completer<void>? gate;

  @override
  Future<DevicePosition?> currentPosition({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final wait = gate;
    if (wait != null) await wait.future;
    return position;
  }
}

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
        location: FakeLocationService(),
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

    test('taken off duty by the backend: offline, without telling it '
        'again', () async {
      await vm.setOnline(true);
      vm.markOffDuty();

      check(vm.isOnline).isFalse();
      check(vm.requests).isEmpty();
      check(repo.duty).deepEquals([true]);
      // Polls stop: a refresh while offline reads nothing.
      await vm.refresh(locate: true);
      check(repo.duty).deepEquals([true]);
    });

    test('accepting hands the ride over and drops it from the feed', () async {
      await vm.setOnline(true);
      final error = await vm.accept(vm.requests.first);

      check(error).isNull();
      check(vm.requests.map((r) => r.id)).deepEquals(['b']);
      check(handedOver.single.status).equals(RideStatus.accepted);
    });

    test('losing the race drops the ride with the backend message', () async {
      repo.failures[RideAction.accept] = const RidesException(
        'This ride is no longer available.',
        code: 'ride_unavailable',
      );
      await vm.setOnline(true);
      final error = await vm.accept(vm.requests.first);

      check(error).equals('This ride is no longer available.');
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

  group('DutyViewModel races', () {
    test('going offline mid-refresh is not undone by that refresh', () async {
      final repo = FakeRidesRepository()..openRides = [ride(id: 'a')];
      final location = _GatedLocation();
      final vm = DutyViewModel(
        repository: repo,
        location: location,
        pollEvery: const Duration(hours: 1),
      );
      addTearDown(vm.dispose);
      await vm.setOnline(true);

      // The poll is still waiting on a GPS fix when the driver goes offline.
      final gate = location.gate = Completer<void>();
      final polling = vm.refresh(locate: true);
      await vm.setOnline(false);
      gate.complete();
      await polling;

      check(repo.duty).deepEquals([true, false]);
      check(vm.isOnline).isFalse();
      check(vm.requests).isEmpty();
    });

    test('signing out while going online starts no poll', () async {
      final repo = FakeRidesRepository();
      final location = _GatedLocation();
      final vm = DutyViewModel(
        repository: repo,
        location: location,
        pollEvery: const Duration(milliseconds: 5),
      );

      final gate = location.gate = Completer<void>();
      final going = vm.setOnline(true);
      vm.dispose();
      gate.complete();
      await going;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Nothing reported this driver online, then or on a leaked timer.
      check(repo.duty).isEmpty();
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

    test('a cancelled ride is listed separately, not anywhere else', () async {
      final repo = FakeRidesRepository()
        ..mine = [
          ride(id: 'up', status: 'accepted'),
          ride(
            id: 'cancelled',
            status: 'cancelled',
            cancelledAt: '2026-10-25T08:00:00+05:30',
            cancelledBy: 'customer',
            cancelReason: 'Plans changed',
          ),
        ];
      final vm = MyRidesViewModel(repository: repo);
      await vm.load();

      check(vm.cancelled.map((r) => r.id)).deepEquals(['cancelled']);
      check(vm.upcoming.map((r) => r.id)).deepEquals(['up']);
      check(vm.ongoing).isEmpty();
      check(vm.completed).isEmpty();
      final cancelledRide = vm.byId('cancelled')!;
      check(cancelledRide.cancelledBy).equals('customer');
      check(cancelledRide.cancelReason).equals('Plans changed');
    });

    test(
      'rating a completed ride sends stars and note, then upserts',
      () async {
        final repo = FakeRidesRepository()
          ..mine = [ride(id: 'r', status: 'completed')];
        final vm = MyRidesViewModel(repository: repo);
        await vm.load();

        final error = await vm.act(
          vm.byId('r')!,
          RideAction.rate,
          stars: 4,
          note: 'Great customer',
        );

        check(error).isNull();
        check(repo.lastRating).equals((4, 'Great customer'));
        check(vm.byId('r')!.myRating!.stars).equals(4);
        check(vm.byId('r')!.myRating!.note).equals('Great customer');
      },
    );

    test('rating errors get friendly messages', () async {
      final repo = FakeRidesRepository()
        ..mine = [ride(id: 'r', status: 'completed')];
      final vm = MyRidesViewModel(repository: repo);
      await vm.load();

      repo.failures[RideAction.rate] = const RidesException(
        'stars must be between 1 and 5',
        code: 'invalid_rating',
      );
      check(
        await vm.act(vm.byId('r')!, RideAction.rate, stars: 0),
      ).equals('Pick 1 to 5 stars for the customer.');

      repo.failures[RideAction.rate] = const RidesException(
        'ride already rated',
        code: 'ride_state',
      );
      check(
        await vm.act(vm.byId('r')!, RideAction.rate, stars: 4),
      ).equals("This ride can't be rated right now.");
    });

    test('a slow load does not undo steps taken while it ran', () async {
      final repo = _GatedRides()
        ..mine = [
          ride(id: 'stay', status: 'accepted'),
          ride(id: 'gone', status: 'accepted'),
        ];
      final vm = MyRidesViewModel(repository: repo);
      await vm.load();

      // The poll's answer was read before the driver arrived and handed one
      // back, and lands after both.
      final gate = repo.gate = Completer<void>();
      final polling = vm.load();
      check(await vm.act(vm.byId('stay')!, RideAction.arrive)).isNull();
      check(await vm.act(vm.byId('gone')!, RideAction.release)).isNull();
      gate.complete();
      await polling;

      check(vm.byId('stay')!.status).equals(RideStatus.arrived);
      check(vm.byId('gone')).isNull();
      check(vm.isLoading).isFalse();
    });

    test('only the latest of two overlapping loads is used', () async {
      final repo = _GatedRides()..mine = [ride(id: 'r', status: 'accepted')];
      final vm = MyRidesViewModel(repository: repo);

      final older = repo.gate = Completer<void>();
      final first = vm.load();
      repo
        ..gate = null
        ..mine = [ride(id: 'r', status: 'arrived')];
      await vm.load();
      older.complete();
      await first;

      check(vm.byId('r')!.status).equals(RideStatus.arrived);
    });

    test('a load settling after a sign-out notifies no one', () async {
      final repo = _GatedRides()..mine = [ride(id: 'r', status: 'accepted')];
      final rides = MyRidesViewModel(repository: repo);
      final earnings = EarningsViewModel(repository: repo);

      final gate = repo.gate = Completer<void>();
      final loads = Future.wait([rides.load(), earnings.load()]);
      rides.dispose();
      earnings.dispose();
      gate.complete();

      await loads;
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

    test('reads ratings', () {
      check(RideFormat.customerRating(null, 0)).equals('New customer');
      check(RideFormat.customerRating(4.9, 3)).equals('★ 4.9 · 3 ratings');
      check(RideFormat.customerRating(5.0, 1)).equals('★ 5.0 · 1 rating');

      check(RideFormat.driverRating(null)).equals('No ratings yet');
      check(
        RideFormat.driverRating(const EarningsRating(average: 4.8, count: 12)),
      ).equals('Your rating ★ 4.8 from 12 trips');
      check(
        RideFormat.driverRating(const EarningsRating(average: 5, count: 1)),
      ).equals('Your rating ★ 5.0 from 1 trip');
    });
  });
}
