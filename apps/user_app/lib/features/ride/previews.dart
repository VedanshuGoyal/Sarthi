import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'data/location_repository.dart';
import 'domain/geo_point.dart';
import 'domain/pickup_location.dart';
import 'domain/place_suggestion.dart';
import 'domain/trip_type.dart';
import 'ride_providers.dart';
import 'view/pickup_location_screen.dart';
import 'view/trip_type_selector.dart';
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

@Preview(name: 'Nothing selected', group: 'Trip chooser', theme: ridePreviewTheme)
Widget tripChooserUnselectedPreview() => _seeded();

@Preview(name: 'Round trip', group: 'Trip chooser', theme: ridePreviewTheme)
Widget tripChooserRoundTripPreview() =>
    _seeded(initialType: TripType.roundTrip);

@Preview(name: 'Multi-stop', group: 'Trip chooser', theme: ridePreviewTheme)
Widget tripChooserMultiStopPreview() =>
    _seeded(initialType: TripType.multiStop);

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
  PickupLocation? selected,
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
          initialSelected: selected,
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

@Preview(name: 'Pickup selected', group: 'Pickup', theme: ridePreviewTheme)
Widget pickupSelectedPreview() => _pickup(
  query: 'MG Road, Bengaluru, Karnataka',
  selected: const PickupLocation(
    address: 'MG Road, Bengaluru, Karnataka',
    point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
    placeId: 'p1',
  ),
);
