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

  test('starts sharing once a ride enters the window, and sends fixes', () async {
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();
    check(vm.isSharing).isTrue();

    location.emit((lat: 28.6, lng: 77.2, heading: 90.0));
    await Future<void>.delayed(Duration.zero);

    check(repo.sharedLocations).length.equals(1);
    check(repo.sharedLocations.single).equals((28.6, 77.2, 90.0));
    vm.dispose();
  });

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

  test('more than 60 minutes before pickup, nothing is shared', () async {
    now = DateTime.parse('2026-10-26T07:30:00+05:30'); // 90 min out
    repo.mine = [ride(id: 'r', status: 'accepted', scheduledAt: scheduledAt)];
    await myRides.load();
    final vm = buildVm();

    check(vm.isSharing).isFalse();
    vm.dispose();
  });
}
