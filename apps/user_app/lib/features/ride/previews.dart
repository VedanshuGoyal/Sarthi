import 'dart:async';

import 'package:flutter/material.dart' show Material, TimeOfDay;
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'data/location_repository.dart';
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
import 'view/one_way_review_screen.dart';
import 'view/pickup_location_screen.dart';
import 'view/trip_type_selector.dart';
import 'view/widgets/fare_summary.dart';
import 'view/widgets/map_pin_card.dart';
import 'view/widgets/time_slot_picker.dart';
import 'view_model/booking_details_view_model.dart';
import 'view_model/multi_stop_planner_view_model.dart';
import 'view_model/one_way_details_view_model.dart';
import 'view_model/one_way_review_view_model.dart';
import 'view_model/pickup_selection_view_model.dart';
import 'view_model/trip_selection_view_model.dart';

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
  _PreviewLocationRepository({this.recents = const []})
    : super(tokenProvider: _token);

  final List<PickupLocation> recents;

  static Future<String> _token() async => 'preview';

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
    primaryText: 'MG Road',
    secondaryText: 'Bengaluru, Karnataka',
    address: 'MG Road, Bengaluru, Karnataka',
    point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
  ),
  PlaceSuggestion(
    placeId: 'p2',
    primaryText: 'MG Road Metro Station',
    secondaryText: 'Trinity Circle, Bengaluru',
    address: 'MG Road Metro Station, Trinity Circle, Bengaluru',
    point: GeoPoint(latitude: 12.9757, longitude: 77.6199),
  ),
  PlaceSuggestion(
    placeId: 'p3',
    primaryText: 'Mahatma Gandhi Road',
    secondaryText: 'Shivaji Nagar, Bengaluru',
    address: 'Mahatma Gandhi Road, Shivaji Nagar, Bengaluru',
    point: GeoPoint(latitude: 12.9820, longitude: 77.6050),
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
    address: 'Home — 4th Block, Koramangala, Bengaluru',
    point: GeoPoint(latitude: 12.9352, longitude: 77.6245),
    placeId: 'r1',
  ),
  PickupLocation(
    address: 'Kempegowda International Airport, Bengaluru',
    point: GeoPoint(latitude: 13.1986, longitude: 77.7066),
    placeId: 'r2',
  ),
];

@Preview(name: 'Empty', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupEmptyPreview() => _pickup();

@Preview(name: 'Recent pickups', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupRecentsPreview() => _pickup(recents: _sampleRecents);

@Preview(name: 'With results', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupResultsPreview() =>
    _pickup(query: 'MG Road', suggestions: _sampleSuggestions);

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
    label: 'MG Road, Bengaluru, Karnataka',
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
    label: '12.9756, 77.6068',
    isMoving: false,
    isResolving: true,
    canConfirm: false,
  ),
);

@Preview(name: 'Pin — error', group: 'Map picker', theme: ridePreviewTheme)
Widget mapPinErrorPreview() => _pinCard(
  const MapPinCard(
    label: '12.9756, 77.6068',
    isMoving: false,
    isResolving: false,
    error: 'The maps service is unavailable right now. Please try again.',
    canConfirm: false,
  ),
);

// --- Booking details step --------------------------------------------------
// The Round Trip "how long / when / which car" step. Each preview seeds the
// view model's state directly via a family override, so states render in
// isolation without tapping through the pickers.

const _bookingPickup = PickupLocation(
  address: 'MG Road, Bengaluru, Karnataka',
  point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
  placeId: 'p1',
);

Widget _booking({
  int hours = 2,
  DateTime? scheduledAt,
  CarType? carType,
  Transmission transmission = Transmission.automatic,
}) {
  return ProviderScope(
    overrides: [
      bookingDetailsViewModelProvider.overrideWith(
        (ref, pickup) => BookingDetailsViewModel(
          pickup: pickup,
          initialHours: hours,
          initialScheduledAt: scheduledAt,
          initialCarType: carType,
          initialTransmission: transmission,
        ),
      ),
    ],
    child: const BookingDetailsScreen(pickup: _bookingPickup),
  );
}

@Preview(name: 'Empty', group: 'Booking details', theme: ridePreviewTheme)
Widget bookingEmptyPreview() => _booking();

@Preview(name: 'Car chosen', group: 'Booking details', theme: ridePreviewTheme)
Widget bookingCarChosenPreview() => _booking(hours: 4, carType: CarType.sedan);

@Preview(name: 'Ready', group: 'Booking details', theme: ridePreviewTheme)
Widget bookingReadyPreview() => _booking(
  hours: 6,
  scheduledAt: DateTime(2026, 7, 18, 9, 30),
  carType: CarType.suv,
  transmission: Transmission.manual,
);

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
    address: 'Apollo Pharmacy, Indiranagar, Bengaluru',
    point: GeoPoint(latitude: 12.9719, longitude: 77.6412),
    placeId: 's1',
  ),
  task: 'Collect the prescription refill under the name Sharma.',
);

const _plannerStopTwo = StopDraft(
  id: 1,
  location: PickupLocation(
    address: 'Passport Seva Kendra, Lalbagh Road, Bengaluru',
    point: GeoPoint(latitude: 12.9581, longitude: 77.5850),
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
  address: 'Kempegowda International Airport, Bengaluru',
  point: GeoPoint(latitude: 13.1986, longitude: 77.7066),
  placeId: 'r2',
);

Widget _oneWay({
  DateTime? scheduledAt,
  CarType? carType,
  Transmission transmission = Transmission.automatic,
}) {
  return ProviderScope(
    overrides: [
      oneWayDetailsViewModelProvider.overrideWith(
        (ref, route) => OneWayDetailsViewModel(
          route: route,
          initialScheduledAt: scheduledAt,
          initialCarType: carType,
          initialTransmission: transmission,
        ),
      ),
    ],
    child: OneWayDetailsScreen(
      start: _bookingPickup,
      destination: _oneWayDestination,
    ),
  );
}

@Preview(name: 'Awaiting a car', group: 'One-Way details', theme: ridePreviewTheme)
Widget oneWayAwaitingCarPreview() => _oneWay();

@Preview(name: 'Ready', group: 'One-Way details', theme: ridePreviewTheme)
Widget oneWayReadyPreview() => _oneWay(
  scheduledAt: DateTime(2026, 7, 20, 9, 30),
  carType: CarType.sedan,
  transmission: Transmission.manual,
);

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
        carType: CarType.sedan,
        transmission: Transmission.manual,
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
