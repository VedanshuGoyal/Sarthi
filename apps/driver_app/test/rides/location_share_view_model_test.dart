import 'package:checks/checks.dart';
import 'package:driver_app/features/rides/view_model/location_share_view_model.dart';
import 'package:driver_app/features/rides/view_model/my_rides_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeRidesRepository repo;
  late FakeLocationService location;
  late MyRidesViewModel myRides;
  late DateTime now;

  const scheduledAt = '2026-10-26T09:00:00+05:30';

  setUp(() {
    repo = FakeRidesRepository();
    location = FakeLocationService();
    now = DateTime.parse('2026-10-26T08:00:00+05:30'); // exactly 60 min out
    myRides = MyRidesViewModel(repository: repo);
  });

  LocationShareViewModel buildVm() => LocationShareViewModel(
    myRides: myRides,
    location: location,
    repository: repo,
    now: () => now,
    minSendGap: const Duration(seconds: 10),
  );

  test('not sharing when no ride is in the tracking window', () async {
    repo.mine = [ride(id: 'r', status: 'requested', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();

    check(vm.isSharing).isFalse();
    check(repo.sharedLocations).isEmpty();
    vm.dispose();
  });

  test(
    'starts sharing once a ride enters the window, and sends fixes',
    () async {
      repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
      await myRides.load();
      final vm = buildVm();
      check(vm.isSharing).isTrue();

      location.emit((lat: 28.6, lng: 77.2, heading: 90.0));
      await Future<void>.delayed(Duration.zero);

      check(repo.sharedLocations).length.equals(1);
      check(repo.sharedLocations.single).equals((28.6, 77.2, 90.0));
      vm.dispose();
    },
  );

  test('throttles sends to one per minSendGap', () async {
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();

    location.emit((lat: 1, lng: 1, heading: null));
    location.emit((lat: 2, lng: 2, heading: null)); // same instant, throttled
    await Future<void>.delayed(Duration.zero);
    check(repo.sharedLocations).length.equals(1);

    now = now.add(const Duration(seconds: 11));
    location.emit((lat: 3, lng: 3, heading: null));
    await Future<void>.delayed(Duration.zero);
    check(repo.sharedLocations).length.equals(2);
    vm.dispose();
  });

  test('stops sharing once the ride leaves the window', () async {
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();
    check(vm.isSharing).isTrue();

    repo.mine = [ride(id: 'r', status: 'completed', scheduledAt: scheduledAt)];
    await myRides.load();

    check(vm.isSharing).isFalse();
    vm.dispose();
  });

  test('a failed send is ignored quietly — the stream stays open', () async {
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    repo.failShareLocation = true;
    final vm = buildVm();

    location.emit((lat: 1, lng: 1, heading: null));
    await Future<void>.delayed(Duration.zero);

    check(vm.isSharing).isTrue();
    check(repo.sharedLocations).isEmpty();
    vm.dispose();
  });

  // F15: the window is a function of time, but used to be re-checked only
  // when the ride list changed.
  testWidgets('starts sharing when the window opens with the app left open', (
    tester,
  ) async {
    now = DateTime.parse('2026-10-26T07:30:00+05:30'); // 90 min out
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = LocationShareViewModel(
      myRides: myRides,
      location: location,
      repository: repo,
      now: () => now,
      recheckEvery: const Duration(seconds: 30),
    );
    addTearDown(vm.dispose);
    check(vm.isSharing).isFalse();

    now = DateTime.parse('2026-10-26T07:59:50+05:30');
    await tester.pump(const Duration(seconds: 30));
    check(vm.isSharing).isFalse();

    now = DateTime.parse('2026-10-26T08:00:20+05:30'); // inside the window
    await tester.pump(const Duration(seconds: 30));
    check(vm.isSharing).isTrue();
  });

  // testWidgets fails on a timer still pending when the body ends, so these
  // also check that the re-check stops once there is nothing to wait for.
  testWidgets('no ride held, no clock to watch', (tester) async {
    repo.mine = [ride(id: 'r', status: 'completed', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();
    addTearDown(vm.dispose);

    await tester.pump(const Duration(minutes: 5));

    check(vm.isSharing).isFalse();
  });

  testWidgets('a ride released before its window stops the re-check', (
    tester,
  ) async {
    now = DateTime.parse('2026-10-26T07:30:00+05:30'); // 90 min out
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();
    addTearDown(vm.dispose);

    repo.mine = [];
    await myRides.load();
    await tester.pump(const Duration(minutes: 5));

    check(vm.isSharing).isFalse();
  });

  test('more than 60 minutes before pickup, nothing is shared', () async {
    now = DateTime.parse('2026-10-26T07:30:00+05:30'); // 90 min out
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();

    check(vm.isSharing).isFalse();
    vm.dispose();
  });

  test('while sharing, re-reads the rides every rideCheckEvery and stops once '
      'the ride was cancelled', () async {
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();
    check(vm.isSharing).isTrue();
    final before = repo.myRidesCalls;

    location.emit((lat: 28.6, lng: 77.2, heading: 0.0));
    await Future<void>.delayed(Duration.zero);
    check(repo.myRidesCalls).equals(before);

    // A minute later: sent, but the rides aren't read again yet.
    now = now.add(const Duration(minutes: 1));
    location.emit((lat: 28.6, lng: 77.2, heading: 0.0));
    await Future<void>.delayed(Duration.zero);
    check(repo.myRidesCalls).equals(before);

    // The customer cancelled meanwhile; the next check stops sharing.
    repo.mine = [ride(id: 'r', status: 'cancelled', scheduledAt: scheduledAt)];
    now = now.add(const Duration(minutes: 2));
    location.emit((lat: 28.6, lng: 77.2, heading: 0.0));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    check(repo.myRidesCalls).equals(before + 1);
    check(vm.isSharing).isFalse();
    vm.dispose();
  });
}
