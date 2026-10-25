import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'data/booking_repository.dart';
import 'data/cars_api.dart';
import 'data/cars_repository.dart';
import 'data/location_repository.dart';
import 'data/ola_maps_authenticator.dart';
import 'data/recent_pickups_api.dart';
import 'domain/one_way_trip.dart';
import 'domain/pickup_location.dart';
import 'view_model/booking_details_view_model.dart';
import 'view_model/map_pickup_view_model.dart';
import 'view_model/multi_stop_planner_view_model.dart';
import 'view_model/my_bookings_view_model.dart';
import 'view_model/one_way_details_view_model.dart';
import 'view_model/one_way_review_view_model.dart';
import 'view_model/pickup_selection_view_model.dart';
import 'view_model/ride_details_view_model.dart';
import 'view_model/saved_cars_view_model.dart';
import 'view_model/trip_start_view_model.dart';
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
/// Recents and the Ola Maps token both come from the Sarthi backend,
/// authenticated with the current session token read on demand from in-memory
/// auth state (like [authRepositoryProvider]).
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  String? sessionToken() => ref.read(authControllerProvider).valueOrNull?.token;
  return LocationRepository(
    tokenProvider: OlaMapsAuthenticator(tokenGetter: sessionToken).accessToken,
    recentsApi: RecentPickupsApi(tokenGetter: sessionToken),
  );
});

/// The data seam for sending confirmed bookings to the backend, authenticated
/// with the current session token (read on demand, like the recents API).
/// Overridden in tests with a fake so no real request is made.
final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(
    tokenGetter: () => ref.read(authControllerProvider).valueOrNull?.token,
  );
});

/// The customer's bookings for the Activity tab.
/// Rebuilt per signed-in user, so a different account on the same phone never
/// sees the previous one's rides or start codes.
final myBookingsViewModelProvider = ChangeNotifierProvider<MyBookingsViewModel>(
  (ref) {
    ref.watch(authControllerProvider.select((s) => s.valueOrNull?.user.id));
    return MyBookingsViewModel(
      repository: ref.watch(bookingRepositoryProvider),
    );
  },
);

/// One ride's details screen (and the rating sheet): cancel, rate, and the
/// driver's live location. A `family` keyed on the booking id — the ride
/// itself is read from [myBookingsViewModelProvider], so the screen follows
/// every list refresh. `autoDispose` so leaving the screen stops its polling
/// and drops a half-written rating.
final rideDetailsViewModelProvider = ChangeNotifierProvider.autoDispose
    .family<RideDetailsViewModel, String>((ref, bookingId) {
      return RideDetailsViewModel(
        repository: ref.watch(bookingRepositoryProvider),
        bookings: ref.watch(myBookingsViewModelProvider),
        bookingId: bookingId,
      );
    });

/// The data seam for the customer's saved cars: on-device storage first, the
/// backend (authenticated with the current session token, read on demand like
/// the recents API) only for changes or an empty cache. Overridden in previews
/// and tests with a fake so no real request or platform storage is touched.
final carsRepositoryProvider = Provider<CarsRepository>((ref) {
  return CarsRepository(
    api: CarsApi(
      tokenGetter: () => ref.read(authControllerProvider).valueOrNull?.token,
    ),
  );
});

/// The saved-cars view model, shared by the booking steps' dropdown and the
/// profile screen's "My cars" list. Loads the (locally mirrored) list as soon
/// as a screen needs it; `autoDispose` drops it once no screen is listening.
final savedCarsViewModelProvider =
    ChangeNotifierProvider.autoDispose<SavedCarsViewModel>((ref) {
      return SavedCarsViewModel(repository: ref.watch(carsRepositoryProvider))
        ..load();
    });

/// The pickup step's view model. `autoDispose` so a customer who backs out of
/// the pickup screen starts a fresh search next time.
final pickupSelectionViewModelProvider =
    ChangeNotifierProvider.autoDispose<PickupSelectionViewModel>((ref) {
      return PickupSelectionViewModel(
        repository: ref.watch(locationRepositoryProvider),
      );
    });

/// The starting point for One-Way's "From" row and Round Trip's pickup row,
/// located from GPS as soon as the step opens. `autoDispose` so each visit re-checks the current location —
/// quietly, behind the last known spot, after the first fix.
final tripStartViewModelProvider =
    ChangeNotifierProvider.autoDispose<TripStartViewModel>((ref) {
      return TripStartViewModel(
        repository: ref.watch(locationRepositoryProvider),
      )..locate();
    });

/// The map-picker step's view model. `autoDispose` so each visit starts fresh,
/// re-centred on the customer's current location.
final mapPickupViewModelProvider =
    ChangeNotifierProvider.autoDispose<MapPickupViewModel>((ref) {
      return MapPickupViewModel(
        repository: ref.watch(locationRepositoryProvider),
      );
    });

/// The booking-details step's view model (hours, schedule, car).
///
/// `autoDispose` so backing out of the screen resets the choices to their
/// defaults for the next visit. The pickup lives in
/// [tripStartViewModelProvider], so changing it keeps these choices.
final bookingDetailsViewModelProvider =
    ChangeNotifierProvider.autoDispose<BookingDetailsViewModel>((ref) {
      return BookingDetailsViewModel();
    });

/// The Multi-Stop planner's view model (start time + the ordered stop drafts).
///
/// A `family` keyed on the confirmed starting [PickupLocation] — the step's one
/// input, known only at navigation time. `autoDispose` so backing out of the
/// planner discards the half-written plan for the next visit.
final multiStopPlannerViewModelProvider = ChangeNotifierProvider.autoDispose
    .family<MultiStopPlannerViewModel, PickupLocation>((ref, start) {
      return MultiStopPlannerViewModel(start: start);
    });

/// The One-Way details step's view model (schedule + car type). Pure form
/// state — no drive-time request is made until the review step.
///
/// A `family` keyed on the confirmed [OneWayRoute] — the step's one input,
/// known only at navigation time. `autoDispose` so backing out of the screen
/// resets the choices to their defaults for the next visit.
final oneWayDetailsViewModelProvider = ChangeNotifierProvider.autoDispose
    .family<OneWayDetailsViewModel, OneWayRoute>((ref, route) {
      return OneWayDetailsViewModel(route: route);
    });

/// The One-Way review step's view model (the drive-time estimate + confirm).
///
/// A `family` keyed on the [OneWayDraft] settled on the details step — the
/// step's one input, known only at navigation time. The repository lets it
/// fetch the route's traffic-aware driving time for the chosen start time —
/// once, on entry — which becomes the trip's duration. `autoDispose` so
/// backing out discards the estimate; revisiting fetches a fresh one.
final oneWayReviewViewModelProvider = ChangeNotifierProvider.autoDispose
    .family<OneWayReviewViewModel, OneWayDraft>((ref, draft) {
      return OneWayReviewViewModel(
        draft: draft,
        repository: ref.watch(locationRepositoryProvider),
      );
    });
