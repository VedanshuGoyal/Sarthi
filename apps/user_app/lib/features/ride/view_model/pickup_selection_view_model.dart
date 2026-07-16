import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/location_repository.dart';
import '../domain/pickup_location.dart';
import '../domain/place_suggestion.dart';

/// Drives the "set your pickup" step.
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient search
/// state (query, results, spinners, the chosen pickup, any error) and exposes
/// command methods the view calls. It talks only to [LocationRepository] —
/// never to HTTP or the GPS plugin — and debounces typing so a keystroke
/// doesn't fire a request each character.
class PickupSelectionViewModel extends ChangeNotifier {
  /// [initialQuery], [initialSuggestions], and [initialSelected] are seams used
  /// by previews and tests to render a given state without driving the async
  /// flow; production code uses the defaults (empty, nothing selected).
  PickupSelectionViewModel({
    required this._repository,
    this._debounce = const Duration(milliseconds: 500),
    String initialQuery = '',
    List<PlaceSuggestion> initialSuggestions = const [],
    PickupLocation? initialSelected,
  }) : _query = initialQuery,
       _suggestions = initialSuggestions,
       _selected = initialSelected {
    _loadRecents();
  }

  final LocationRepository _repository;
  final Duration _debounce;

  Timer? _debounceTimer;
  bool _disposed = false;

  /// Guards against out-of-order responses: only the newest search may write
  /// results, so a slow earlier request can't clobber a faster later one.
  int _searchSeq = 0;

  String _query;
  String get query => _query;

  List<PlaceSuggestion> _suggestions;
  List<PlaceSuggestion> get suggestions => _suggestions;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  bool _isLocating = false;
  bool get isLocating => _isLocating;

  PickupLocation? _selected;
  PickupLocation? get selected => _selected;

  List<PickupLocation> _recents = const [];

  /// Previously used pickups, most-recent-first — offered when the field is
  /// empty so a common place can be re-picked with no Ola request.
  List<PickupLocation> get recents => _recents;

  String? _error;
  String? get error => _error;

  /// True once a pickup is chosen and its query text is still intact — gates
  /// the confirm CTA. Editing the field after choosing clears the selection.
  bool get canConfirm => _selected != null;

  /// Handles each keystroke in the search field: records the query, drops any
  /// stale selection, and (debounced) refreshes the suggestion list.
  void onQueryChanged(String value) {
    _query = value;
    if (_selected != null && value != _selected!.address) {
      _selected = null;
    }
    _error = null;

    _debounceTimer?.cancel();
    if (value.trim().length < LocationRepository.minQueryLength) {
      _suggestions = const [];
      _isSearching = false;
      _notify();
      return;
    }

    _isSearching = true;
    _notify();
    _debounceTimer = Timer(_debounce, () => _search(value));
  }

  Future<void> _search(String value) async {
    final seq = ++_searchSeq;
    try {
      final results = await _repository.autocomplete(value);
      if (seq != _searchSeq) return; // superseded by a newer keystroke
      _suggestions = results;
    } on LocationException catch (e) {
      if (seq != _searchSeq) return;
      _suggestions = const [];
      _error = e.message;
    } finally {
      if (seq == _searchSeq) {
        _isSearching = false;
        _notify();
      }
    }
  }

  /// Confirms [suggestion] as the pickup. Ola predictions carry coordinates; a
  /// prediction without them can't be pinned, so we ask the user to try another
  /// rather than guess.
  void selectSuggestion(PlaceSuggestion suggestion) {
    _debounceTimer?.cancel();
    _searchSeq++; // stop any in-flight search from claiming the results

    final point = suggestion.point;
    if (point == null) {
      _error = "Couldn't pin that place. Try another result.";
      _notify();
      return;
    }

    _error = null;
    _applySelection(
      PickupLocation(
        address: suggestion.address,
        point: point,
        placeId: suggestion.placeId,
      ),
    );
  }

  /// Fills the pickup from the device's current GPS position.
  Future<void> useCurrentLocation() async {
    _debounceTimer?.cancel();
    _searchSeq++;
    _isLocating = true;
    _error = null;
    _notify();
    try {
      _applySelection(await _repository.currentLocation());
    } on LocationException catch (e) {
      _error = e.message;
    } finally {
      _isLocating = false;
      _notify();
    }
  }

  /// Picks a saved recent as the pickup. No network call — recents already
  /// carry their coordinates.
  void selectRecent(PickupLocation pickup) {
    _debounceTimer?.cancel();
    _searchSeq++;
    _error = null;
    _applySelection(pickup);
  }

  /// Adopts a pickup the customer pinned on the map. Already resolved to an
  /// address + coordinates by the map step, so — like a recent — it needs no
  /// further lookup; it just becomes the selection and fills the search field.
  void selectFromMap(PickupLocation pickup) {
    _debounceTimer?.cancel();
    _searchSeq++;
    _error = null;
    _applySelection(pickup);
  }

  /// Persists the current selection to recents. Best-effort: a failed save must
  /// not block the customer from using the pickup they just chose.
  Future<void> rememberSelected() async {
    final pickup = _selected;
    if (pickup == null) return;
    try {
      _recents = await _repository.rememberPickup(pickup);
      _notify();
    } catch (_) {
      // Swallow: the pickup is still usable even if we couldn't save it.
    }
  }

  /// Loads recents offline-first: paint the on-device cache immediately, then
  /// refresh from the backend in the background and reconcile. The refresh only
  /// touches [_recents] (never the selection or query), so updating it late is
  /// safe even after the customer has started typing.
  Future<void> _loadRecents() async {
    try {
      final cached = await _repository.cachedRecents();
      if (cached.isNotEmpty) {
        _recents = cached;
        _notify();
      }
    } catch (_) {
      // No cache yet — the backend refresh below will fill it in.
    }

    try {
      _recents = await _repository.recentPickups();
      _notify();
    } catch (_) {
      // Offline and nothing cached: keep whatever we already showed.
    }
  }

  void _applySelection(PickupLocation location) {
    _selected = location;
    _query = location.address;
    _suggestions = const [];
    _isSearching = false;
    _isLocating = false;
    _notify();
  }

  /// Notifies listeners only while still mounted. This view model is
  /// `autoDispose`, so a background refresh (or an in-flight search) can complete
  /// after the pickup screen — and this notifier — is gone; notifying then would
  /// throw.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
