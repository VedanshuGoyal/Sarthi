import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'data/location_repository.dart';
import 'data/recent_pickups_api.dart';
import 'view_model/pickup_selection_view_model.dart';
import 'view_model/trip_selection_view_model.dart';

/// The trip-type chooser's view model.
///
/// `ChangeNotifierProvider` adapts our MVVM [ChangeNotifier] into Riverpod so
/// views can `watch` it for rebuilds. `autoDispose` resets the selection once
/// no screen is listening, so a customer who backs out starts fresh next time.
final tripSelectionViewModelProvider =
    ChangeNotifierProvider.autoDispose<TripSelectionViewModel>((ref) {
      return TripSelectionViewModel();
    });

/// The single data-access seam for pickup search + GPS + recents. Overridden in
/// previews and tests with a fake so no real Ola/GPS/backend call is made.
///
/// Recents hit the Sarthi backend authenticated with the current session token,
/// read on demand from in-memory auth state (like [authRepositoryProvider]).
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    recentsApi: RecentPickupsApi(
      tokenGetter: () => ref.read(authControllerProvider).valueOrNull?.token,
    ),
  );
});

/// The pickup step's view model. `autoDispose` so a customer who backs out of
/// the pickup screen starts a fresh search next time.
final pickupSelectionViewModelProvider =
    ChangeNotifierProvider.autoDispose<PickupSelectionViewModel>((ref) {
      return PickupSelectionViewModel(
        repository: ref.watch(locationRepositoryProvider),
      );
    });
