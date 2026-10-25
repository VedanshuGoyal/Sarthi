import 'dart:async';

import 'package:flutter/material.dart' show Material, TimeOfDay;
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'data/cars_repository.dart';
import 'data/location_repository.dart';
import 'domain/car.dart';
import 'domain/car_type.dart';
import 'domain/geo_point.dart';
import 'domain/pickup_location.dart';
import 'domain/place_suggestion.dart';
import 'domain/transmission.dart';
import 'domain/trip_type.dart';
import 'ride_providers.dart';
import 'view/booking_details_screen.dart';
import 'view/multi_stop_planner_screen.dart';
import 'view/one_way_details_screen.dart';
import 'view/one_way_route_screen.dart';
import 'view/one_way_review_screen.dart';
import 'view/pickup_location_screen.dart';
import 'view/trip_type_selector.dart';
import 'view/widgets/add_car_sheet.dart';
import 'view/widgets/car_selector_field.dart';
import 'view/widgets/fare_summary.dart';
import 'view/widgets/map_pin_card.dart';
import 'view/widgets/time_slot_picker.dart';
import 'view_model/booking_details_view_model.dart';
import 'view_model/multi_stop_planner_view_model.dart';
import 'view_model/one_way_details_view_model.dart';
import 'view_model/one_way_review_view_model.dart';
import 'view_model/pickup_selection_view_model.dart';
import 'view_model/saved_cars_view_model.dart';
import 'view_model/trip_selection_view_model.dart';
import 'view_model/trip_start_view_model.dart';

/// Shared Sarthi theme applied to every ride-flow preview.
PreviewThemeData ridePreviewTheme() => PreviewThemeData(
  materialLight: SarthiTheme.light(),
  materialDark: SarthiTheme.dark(),
);

/// Wraps the selector in a Riverpod scope whose view model starts with
/// [initialType] selected, so each selection state can be previewed in
/// isolation without tapping through the UI.
Widget _seeded({TripType? initialType}) {
  return ProviderScope(
    overrides: [
      tripSelectionViewModelProvider.overrideWith(
        (ref) => TripSelectionViewModel(initialType: initialType),
      ),
    ],
    // Padding/alignment stand in for the landing screen's scaffold so the
    // embeddable selector has somewhere to lay out.
    child: const Padding(
      padding: EdgeInsets.all(24),
      child: Align(alignment: Alignment.topCenter, child: TripTypeSelector()),
    ),
  );
}

@Preview(
  name: 'Nothing selected',
  group: 'Trip chooser',
  theme: ridePreviewTheme,
)
Widget tripChooserUnselectedPreview() => _seeded();

@Preview(name: 'Round trip', group: 'Trip chooser', theme: ridePreviewTheme)
Widget tripChooserRoundTripPreview() =>
    _seeded(initialType: TripType.roundTrip);

@Preview(name: 'Multi-stop', group: 'Trip chooser', theme: ridePreviewTheme)
Widget tripChooserMultiStopPreview() =>
    _seeded(initialType: TripType.multiStop);

@Preview(name: 'One-way', group: 'Trip chooser', theme: ridePreviewTheme)
Widget tripChooserOneWayPreview() => _seeded(initialType: TripType.oneWay);

// --- Pickup step -----------------------------------------------------------

/// Stand-in repository so pickup previews render without any Ola/GPS call.
/// The previews seed the view model's state directly, so its methods are unused.
class _PreviewLocationRepository extends LocationRepository {
  _PreviewLocationRepository({this.recents = const [], this.current})
    : super(tokenProvider: _token);

  final List<PickupLocation> recents;

  /// The GPS fix to report; null keeps the fix pending forever, so a preview
  /// can show the "locating" state (and never touches the GPS plugin).
  final PickupLocation? current;

  static Future<String> _token() async => 'preview';

  @override
  Future<PickupLocation> currentLocation() {
    final current = this.current;
    return current == null
        ? Completer<PickupLocation>().future
        : Future.value(current);
  }

  @override
  Future<List<PickupLocation>> cachedRecents() async => recents;

  @override
  Future<List<PickupLocation>> recentPickups() async => recents;

  @override
  Future<List<PickupLocation>> rememberPickup(PickupLocation pickup) async =>
      recents;
}

const _sampleSuggestions = [
  PlaceSuggestion(
    placeId: 'p1',
    primaryText: 'Connaught Place',
    secondaryText: 'New Delhi, Delhi',
    address: 'Connaught Place, New Delhi, Delhi',
    point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
  ),
  PlaceSuggestion(
    placeId: 'p2',
    primaryText: 'Rajiv Chowk Metro Station',
    secondaryText: 'Connaught Place, New Delhi',
    address: 'Rajiv Chowk Metro Station, Connaught Place, New Delhi',
    point: GeoPoint(latitude: 28.6328, longitude: 77.2197),
  ),
  PlaceSuggestion(
    placeId: 'p3',
    primaryText: 'Connaught Circus',
    secondaryText: 'Barakhamba Road, New Delhi',
    address: 'Connaught Circus, Barakhamba Road, New Delhi',
    point: GeoPoint(latitude: 28.6304, longitude: 77.2211),
  ),
];

/// Hosts [PickupLocationScreen] in a Riverpod scope whose view model starts in
/// the given state, so each state renders in isolation.
Widget _pickup({
  String query = '',
  List<PlaceSuggestion> suggestions = const [],
  List<PickupLocation> recents = const [],
}) {
  return ProviderScope(
    overrides: [
      locationRepositoryProvider.overrideWithValue(
        _PreviewLocationRepository(recents: recents),
      ),
      pickupSelectionViewModelProvider.overrideWith(
        (ref) => PickupSelectionViewModel(
          repository: ref.watch(locationRepositoryProvider),
          initialQuery: query,
          initialSuggestions: suggestions,
        ),
      ),
    ],
    child: const PickupLocationScreen(),
  );
}

const _sampleRecents = [
  PickupLocation(
    address: 'Home — Block C, Vasant Kunj, New Delhi',
    point: GeoPoint(latitude: 28.5245, longitude: 77.1588),
    placeId: 'r1',
  ),
  PickupLocation(
    address: 'Indira Gandhi International Airport, New Delhi',
    point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
    placeId: 'r2',
  ),
];

@Preview(name: 'Empty', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupEmptyPreview() => _pickup();

@Preview(name: 'Recent pickups', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupRecentsPreview() => _pickup(recents: _sampleRecents);

@Preview(name: 'With results', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupResultsPreview() =>
    _pickup(query: 'Connaught Place', suggestions: _sampleSuggestions);

// --- One-Way route step ----------------------------------------------------
// "From" pre-filled from GPS above the destination search.

/// Hosts [OneWayRouteScreen] with GPS reporting [current] (pending when null).
Widget _route({PickupLocation? current}) => ProviderScope(
  overrides: [
    locationRepositoryProvider.overrideWithValue(
      _PreviewLocationRepository(recents: _sampleRecents, current: current),
    ),
  ],
  child: const OneWayRouteScreen(),
);

@Preview(
  name: 'From current location',
  group: 'One-Way route',
  theme: ridePreviewTheme,
)
Widget routeLocatedPreview() => _route(
  current: const PickupLocation(
    address: 'Block C, Vasant Kunj, New Delhi',
    point: GeoPoint(latitude: 28.5245, longitude: 77.1588),
  ),
);

@Preview(name: 'Locating', group: 'One-Way route', theme: ridePreviewTheme)
Widget routeLocatingPreview() => _route();

// --- Map picker card -------------------------------------------------------
// The card that docks over the map. Previewed on its own (away from the
// platform map view) across the states the map step puts it through.

/// Bottom-aligns the card over a neutral backdrop, as it sits on the map.
Widget _pinCard(MapPinCard card) => ColoredBox(
  color: const Color(0xFFB0BEC5),
  child: Align(alignment: Alignment.bottomCenter, child: card),
);

@Preview(name: 'Pin — resolved', group: 'Map picker', theme: ridePreviewTheme)
Widget mapPinResolvedPreview() => _pinCard(
  const MapPinCard(
    label: 'Connaught Place, New Delhi, Delhi',
    isMoving: false,
    isResolving: false,
    canConfirm: true,
  ),
);

@Preview(name: 'Pin — moving', group: 'Map picker', theme: ridePreviewTheme)
Widget mapPinMovingPreview() => _pinCard(
  const MapPinCard(
    label: '',
    isMoving: true,
    isResolving: false,
    canConfirm: false,
  ),
);

@Preview(name: 'Pin — resolving', group: 'Map picker', theme: ridePreviewTheme)
Widget mapPinResolvingPreview() => _pinCard(
  const MapPinCard(
    label: '28.6315, 77.2167',
    isMoving: false,
    isResolving: true,
    canConfirm: false,
  ),
);

@Preview(name: 'Pin — error', group: 'Map picker', theme: ridePreviewTheme)
Widget mapPinErrorPreview() => _pinCard(
  const MapPinCard(
    label: '28.6315, 77.2167',
    isMoving: false,
    isResolving: false,
    error: 'The maps service is unavailable right now. Please try again.',
    canConfirm: false,
  ),
);

// --- Saved cars ------------------------------------------------------------
// The customer's cars offered on every booking step's "which car?" dropdown.

const _carSedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

const _carSuv = Car(
  id: 'c2',
  registration: 'DL05MN0007',
  type: CarType.suv,
  transmission: Transmission.automatic,
);

const _sampleCars = [_carSedan, _carSuv];

/// Seeds the shared saved-cars view model with a canned list so booking-step
/// previews render without a network call. The repository is never invoked —
/// the seeded state skips [SavedCarsViewModel.load].
Override _savedCars({List<Car> cars = _sampleCars}) =>
    savedCarsViewModelProvider.overrideWith(
      (ref) =>
          SavedCarsViewModel(repository: CarsRepository(), initialCars: cars),
    );

// --- Booking details step --------------------------------------------------
// The Round Trip "how long / when / which car" step. Each preview seeds the
// view model's state directly via a family override, so states render in
// isolation without tapping through the pickers.

const _bookingPickup = PickupLocation(
  address: 'Connaught Place, New Delhi, Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
  placeId: 'p1',
);

Widget _booking({
  int hours = 2,
  DateTime? scheduledAt,
  Car? car,
  List<Car> cars = _sampleCars,
}) {
  return ProviderScope(
    overrides: [
      _savedCars(cars: cars),
      tripStartViewModelProvider.overrideWith(
        (ref) => TripStartViewModel(
          repository: _PreviewLocationRepository(),
          initialStart: _bookingPickup,
        ),
      ),
      bookingDetailsViewModelProvider.overrideWith(
        (ref) => BookingDetailsViewModel(
          initialHours: hours,
          initialScheduledAt: scheduledAt,
          initialCar: car,
        ),
      ),
    ],
    child: const BookingDetailsScreen(),
  );
}

@Preview(
  name: 'No saved cars',
  group: 'Booking details',
  theme: ridePreviewTheme,
)
Widget bookingNoCarsPreview() => _booking(cars: const []);

@Preview(name: 'Empty', group: 'Booking details', theme: ridePreviewTheme)
Widget bookingEmptyPreview() => _booking();

@Preview(name: 'Car chosen', group: 'Booking details', theme: ridePreviewTheme)
Widget bookingCarChosenPreview() => _booking(hours: 4, car: _carSedan);

@Preview(name: 'Ready', group: 'Booking details', theme: ridePreviewTheme)
Widget bookingReadyPreview() =>
    _booking(hours: 6, scheduledAt: DateTime(2026, 7, 18, 9, 30), car: _carSuv);

// --- Multi-Stop planner ----------------------------------------------------
// The "write the driver's day" step. Each preview seeds the view model's stop
// drafts directly via a family override, so states render in isolation.

Widget _planner({DateTime? scheduledAt, List<StopDraft>? stops}) {
  return ProviderScope(
    overrides: [
      multiStopPlannerViewModelProvider.overrideWith(
        (ref, start) => MultiStopPlannerViewModel(
          start: start,
          initialScheduledAt: scheduledAt ?? DateTime(2026, 7, 18, 9, 0),
          initialStops: stops,
        ),
      ),
    ],
    child: const MultiStopPlannerScreen(start: _bookingPickup),
  );
}

const _plannerStopOne = StopDraft(
  id: 0,
  location: PickupLocation(
    address: 'Apollo Pharmacy, Lajpat Nagar, New Delhi',
    point: GeoPoint(latitude: 28.5677, longitude: 77.2433),
    placeId: 's1',
  ),
  task: 'Collect the prescription refill under the name Sharma.',
);

const _plannerStopTwo = StopDraft(
  id: 1,
  location: PickupLocation(
    address: 'Passport Seva Kendra, Bhikaji Cama Place, New Delhi',
    point: GeoPoint(latitude: 28.5679, longitude: 77.1859),
    placeId: 's2',
  ),
  task: 'Drop the signed forms at counter 4.',
);

@Preview(
  name: 'One empty stop',
  group: 'Multi-Stop planner',
  theme: ridePreviewTheme,
)
Widget plannerEmptyPreview() => _planner();

@Preview(
  name: 'Half planned',
  group: 'Multi-Stop planner',
  theme: ridePreviewTheme,
)
Widget plannerHalfPlannedPreview() => _planner(
  stops: [
    StopDraft(
      id: 0,
      location: _plannerStopOne.location,
      task: _plannerStopOne.task,
      departBy: DateTime(2026, 7, 18, 10, 30),
    ),
    _plannerStopTwo,
  ],
);

@Preview(name: 'Ready', group: 'Multi-Stop planner', theme: ridePreviewTheme)
Widget plannerReadyPreview() => _planner(
  stops: [
    StopDraft(
      id: 0,
      location: _plannerStopOne.location,
      task: _plannerStopOne.task,
      departBy: DateTime(2026, 7, 18, 10, 30),
    ),
    StopDraft(
      id: 1,
      location: _plannerStopTwo.location,
      task: _plannerStopTwo.task,
      departBy: DateTime(2026, 7, 18, 12, 15),
    ),
  ],
);

@Preview(
  name: 'Time conflict',
  group: 'Multi-Stop planner',
  theme: ridePreviewTheme,
)
Widget plannerTimeConflictPreview() => _planner(
  stops: [
    StopDraft(
      id: 0,
      location: _plannerStopOne.location,
      task: _plannerStopOne.task,
      departBy: DateTime(2026, 7, 18, 12, 0),
    ),
    // Leaves stop 2 before leaving stop 1 — the planner flags the ordering.
    StopDraft(
      id: 1,
      location: _plannerStopTwo.location,
      task: _plannerStopTwo.task,
      departBy: DateTime(2026, 7, 18, 10, 0),
    ),
  ],
);

// --- One-Way details -------------------------------------------------------
// The One-Way "when / which car" step. Each preview seeds the view model's
// state directly via a family override, so states render in isolation.

const _oneWayDestination = PickupLocation(
  address: 'Indira Gandhi International Airport, New Delhi',
  point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
  placeId: 'r2',
);

Widget _oneWay({DateTime? scheduledAt, Car? car}) {
  return ProviderScope(
    overrides: [
      _savedCars(),
      oneWayDetailsViewModelProvider.overrideWith(
        (ref, route) => OneWayDetailsViewModel(
          route: route,
          initialScheduledAt: scheduledAt,
          initialCar: car,
        ),
      ),
    ],
    child: OneWayDetailsScreen(
      start: _bookingPickup,
      destination: _oneWayDestination,
    ),
  );
}

@Preview(
  name: 'Awaiting a car',
  group: 'One-Way details',
  theme: ridePreviewTheme,
)
Widget oneWayAwaitingCarPreview() => _oneWay();

@Preview(name: 'Ready', group: 'One-Way details', theme: ridePreviewTheme)
Widget oneWayReadyPreview() =>
    _oneWay(scheduledAt: DateTime(2026, 7, 20, 9, 30), car: _carSedan);

// --- One-Way review --------------------------------------------------------
// The One-Way "estimated trip time" step that follows the details form. The
// draft is fixed; each preview seeds the estimate's state via a family
// override: checking (a request that never resolves), known (a seeded
// duration, no request), or failed (a request that rejects).

Widget _oneWayReview({Duration? travelTime, LocationRepository? repository}) {
  return ProviderScope(
    overrides: [
      oneWayReviewViewModelProvider.overrideWith(
        (ref, draft) => OneWayReviewViewModel(
          draft: draft,
          repository: repository,
          initialTravelTime: travelTime,
        ),
      ),
    ],
    child: OneWayReviewScreen(
      draft: (
        start: _bookingPickup,
        destination: _oneWayDestination,
        scheduledAt: DateTime(2026, 7, 20, 9, 30),
        car: _carSedan,
      ),
    ),
  );
}

/// A repository whose drive-time request either rejects (the review screen's
/// retry state) or never resolves (its checking state), without a network.
class _CannedEtaRepository extends LocationRepository {
  _CannedEtaRepository({required this.fail}) : super(tokenProvider: _noToken);

  /// True to fail the request; false to leave it pending forever.
  final bool fail;

  static Future<String> _noToken() async => 'preview';

  @override
  Future<Duration> travelTime({
    required GeoPoint start,
    required GeoPoint destination,
    DateTime? departureAt,
  }) {
    if (fail) return Future.error(const LocationException('preview'));
    return Completer<Duration>().future;
  }
}

@Preview(name: 'Checking', group: 'One-Way review', theme: ridePreviewTheme)
Widget oneWayReviewCheckingPreview() =>
    _oneWayReview(repository: _CannedEtaRepository(fail: false));

@Preview(
  name: 'Drive time known',
  group: 'One-Way review',
  theme: ridePreviewTheme,
)
Widget oneWayReviewKnownPreview() =>
    _oneWayReview(travelTime: const Duration(hours: 1, minutes: 25));

@Preview(
  name: 'Estimate failed',
  group: 'One-Way review',
  theme: ridePreviewTheme,
)
Widget oneWayReviewFailedPreview() =>
    _oneWayReview(repository: _CannedEtaRepository(fail: true));

// --- Time slot picker ------------------------------------------------------
// The quarter-hour start-time sheet, as the booking screens open it.

/// Preview seam: slot taps go nowhere outside a live sheet.
void ignoreSlot(TimeOfDay slot) {}

@Preview(name: 'Time slots', group: 'Booking details', theme: ridePreviewTheme)
Widget timeSlotPickerPreview() => const Align(
  alignment: Alignment.bottomCenter,
  child: Material(
    child: TimeSlotPicker(
      selected: TimeOfDay(hour: 9, minute: 30),
      onSelected: ignoreSlot,
    ),
  ),
);

// --- Fare summary ----------------------------------------------------------
// The estimated-fare readout from the booking step's bottom bar, on its own.

/// Frames the summary as it sits in the action bar: full-width over a surface.
Widget _fare(FareSummary summary) => Padding(
  padding: const EdgeInsets.all(24),
  child: Align(alignment: Alignment.topCenter, child: summary),
);

@Preview(
  name: 'Preview (no car)',
  group: 'Fare summary',
  theme: ridePreviewTheme,
)
Widget farePreviewApproximate() =>
    _fare(const FareSummary(fare: 340, hours: 3, approximate: true));

@Preview(name: 'Standard', group: 'Fare summary', theme: ridePreviewTheme)
Widget fareStandardPreview() => _fare(const FareSummary(fare: 340, hours: 3));

@Preview(name: 'Luxury', group: 'Fare summary', theme: ridePreviewTheme)
Widget fareLuxuryPreview() => _fare(const FareSummary(fare: 440, hours: 3));

// --- Car selector ----------------------------------------------------------
// The saved-car dropdown the booking steps share, across its states.

/// Preview seams: picks/taps go nowhere outside a live booking step.
void ignoreCar(Car car) {}
void ignoreTap() {}

/// Frames the field as it sits in a "Which car?" section.
Widget _carSelector({
  List<Car> cars = _sampleCars,
  Car? selected,
  bool isLoading = false,
  bool loadFailed = false,
}) => Padding(
  padding: const EdgeInsets.all(24),
  child: Align(
    alignment: Alignment.topCenter,
    child: CarSelectorField(
      cars: cars,
      selected: selected,
      isLoading: isLoading,
      loadFailed: loadFailed,
      onSelected: ignoreCar,
      onAddCar: ignoreTap,
      onRetry: ignoreTap,
    ),
  ),
);

@Preview(name: 'Loading', group: 'Car selector', theme: ridePreviewTheme)
Widget carSelectorLoadingPreview() => _carSelector(isLoading: true);

@Preview(name: 'Load failed', group: 'Car selector', theme: ridePreviewTheme)
Widget carSelectorFailedPreview() => _carSelector(loadFailed: true);

@Preview(name: 'No cars yet', group: 'Car selector', theme: ridePreviewTheme)
Widget carSelectorEmptyPreview() => _carSelector(cars: const []);

@Preview(name: 'Car picked', group: 'Car selector', theme: ridePreviewTheme)
Widget carSelectorPickedPreview() => _carSelector(selected: _carSedan);

// --- Add-car sheet ---------------------------------------------------------
// The "add a car" form, as the car selector opens it. The saved-cars view
// model is seeded so the sheet renders without a network; saving from a
// preview would hit the stub repository and simply fail.

@Preview(name: 'Add a car', group: 'Car selector', theme: ridePreviewTheme)
Widget addCarSheetPreview() => ProviderScope(
  overrides: [_savedCars()],
  child: const Align(
    alignment: Alignment.bottomCenter,
    child: Material(child: AddCarSheet()),
  ),
);
