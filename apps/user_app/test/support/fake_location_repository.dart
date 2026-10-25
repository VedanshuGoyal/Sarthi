import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/place_suggestion.dart';

/// A [LocationRepository] that returns canned data instead of calling Ola/GPS,
/// so view-model tests exercise the real [PickupSelectionViewModel] logic
/// without a network or device.
class FakeLocationRepository extends LocationRepository {
  FakeLocationRepository({
    this.suggestions = const [],
    this.current,
    this.currentPos,
    this.reverseResult,
    this.autocompleteError,
    this.currentError,
    this.reverseError,
    this.recents = const [],
    this.lastKnown,
  }) : super(tokenProvider: _noToken);

  static Future<String> _noToken() async => 'fake-token';

  /// What [autocomplete] returns for a long-enough query.
  List<PlaceSuggestion> suggestions;

  /// What [currentLocation] resolves to when [currentError] is null.
  PickupLocation? current;

  /// What [currentPoint] returns when [currentError] is null.
  GeoPoint? currentPos;

  /// What [reverseGeocode] resolves to when [reverseError] is null. When null a
  /// pickup is synthesised from the point's coordinates.
  PickupLocation? reverseResult;

  /// When set, [autocomplete] throws this instead of returning [suggestions].
  LocationException? autocompleteError;

  /// When set, [currentLocation]/[currentPoint] throw this instead.
  LocationException? currentError;

  /// When set, [reverseGeocode] throws this instead of resolving.
  LocationException? reverseError;

  /// What [recentPickups] returns and what [rememberPickup] prepends to.
  List<PickupLocation> recents;

  /// What [lastKnownHere] returns — a spot "remembered" from earlier.
  PickupLocation? lastKnown;

  @override
  PickupLocation? get lastKnownHere => lastKnown;

  /// Every query string passed to [autocomplete], in order.
  final List<String> queries = [];

  /// Every point passed to [reverseGeocode], in order.
  final List<GeoPoint> reverseGeocoded = [];

  /// Every pickup passed to [rememberPickup], in order.
  final List<PickupLocation> remembered = [];

  @override
  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    GeoPoint? near,
  }) async {
    queries.add(input);
    if (input.trim().length < LocationRepository.minQueryLength) {
      return const [];
    }
    if (autocompleteError != null) throw autocompleteError!;
    return suggestions;
  }

  @override
  Future<PickupLocation> currentLocation() async {
    if (currentError != null) throw currentError!;
    return current ??
        const PickupLocation(
          address: 'Current place, New Delhi',
          point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
        );
  }

  @override
  Future<GeoPoint> currentPoint() async {
    if (currentError != null) throw currentError!;
    return currentPos ?? const GeoPoint(latitude: 28.6139, longitude: 77.2090);
  }

  @override
  Future<PickupLocation> reverseGeocode(GeoPoint point) async {
    reverseGeocoded.add(point);
    if (reverseError != null) throw reverseError!;
    return reverseResult ??
        PickupLocation(address: 'Pinned place', point: point);
  }

  @override
  Future<List<PickupLocation>> cachedRecents() async => recents;

  @override
  Future<List<PickupLocation>> recentPickups() async => recents;

  @override
  Future<List<PickupLocation>> rememberPickup(PickupLocation pickup) async {
    remembered.add(pickup);
    recents = [pickup, ...recents.where((p) => p.address != pickup.address)];
    return recents;
  }
}
