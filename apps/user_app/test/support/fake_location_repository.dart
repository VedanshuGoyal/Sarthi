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
    this.autocompleteError,
    this.currentError,
    this.recents = const [],
  }) : super(tokenProvider: _noToken);

  static Future<String> _noToken() async => 'fake-token';

  /// What [autocomplete] returns for a long-enough query.
  List<PlaceSuggestion> suggestions;

  /// What [currentLocation] resolves to when [currentError] is null.
  PickupLocation? current;

  /// When set, [autocomplete] throws this instead of returning [suggestions].
  LocationException? autocompleteError;

  /// When set, [currentLocation] throws this instead of returning [current].
  LocationException? currentError;

  /// What [recentPickups] returns and what [rememberPickup] prepends to.
  List<PickupLocation> recents;

  /// Every query string passed to [autocomplete], in order.
  final List<String> queries = [];

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
          address: 'Current place, Bengaluru',
          point: GeoPoint(latitude: 12.9, longitude: 77.6),
        );
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
