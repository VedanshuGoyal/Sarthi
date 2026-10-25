import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location_providers.dart';
import '../auth/driver_auth_controller.dart';
import 'data/rides_repository.dart';
import 'view_model/duty_view_model.dart';
import 'view_model/earnings_view_model.dart';
import 'view_model/location_share_view_model.dart';
import 'view_model/my_rides_view_model.dart';

/// Single shared [RidesRepository]. Like the other repositories, it reads the
/// bearer token on demand from the in-memory session.
final ridesRepositoryProvider = Provider<RidesRepository>((ref) {
  return RidesRepository(
    tokenGetter: () =>
        ref.read(driverAuthControllerProvider).valueOrNull?.token,
  );
});

/// The signed-in driver's id. The view models below watch it so a different
/// driver signing in on the same phone starts from clean state.
final _driverIdProvider = Provider<String?>((ref) {
  return ref.watch(
    driverAuthControllerProvider.select((s) => s.valueOrNull?.driver.id),
  );
});

/// The driver's own rides (the Rides panel, and Home's "next ride" card).
/// Starts loading as soon as it's created, so a fresh instance (after a
/// different driver signs in) is never left empty.
final myRidesViewModelProvider = ChangeNotifierProvider<MyRidesViewModel>((
  ref,
) {
  ref.watch(_driverIdProvider);
  return MyRidesViewModel(
    repository: ref.watch(ridesRepositoryProvider),
    onCompleted: () => ref.read(earningsViewModelProvider).load(),
  )..load();
});

/// The earnings summary. Loads on creation, like [myRidesViewModelProvider].
final earningsViewModelProvider = ChangeNotifierProvider<EarningsViewModel>((
  ref,
) {
  ref.watch(_driverIdProvider);
  return EarningsViewModel(repository: ref.watch(ridesRepositoryProvider))
    ..load();
});

/// On/off duty and the open requests feed. An accepted request moves into
/// [myRidesViewModelProvider].
final dutyViewModelProvider = ChangeNotifierProvider<DutyViewModel>((ref) {
  ref.watch(_driverIdProvider);
  return DutyViewModel(
    repository: ref.watch(ridesRepositoryProvider),
    location: ref.watch(locationServiceProvider),
    onAccepted: (ride) => ref.read(myRidesViewModelProvider).upsert(ride),
  );
});

/// Shares the driver's live location with the customer while a ride is in
/// its tracking window. Created once per driver and read eagerly from the
/// Home shell, so it keeps running whichever tab or screen is open.
final locationShareViewModelProvider =
    ChangeNotifierProvider<LocationShareViewModel>((ref) {
      ref.watch(_driverIdProvider);
      return LocationShareViewModel(
        myRides: ref.watch(myRidesViewModelProvider),
        location: ref.watch(locationServiceProvider),
        repository: ref.watch(ridesRepositoryProvider),
      );
    });
