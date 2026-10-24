import 'package:flutter/foundation.dart';

import '../data/location_repository.dart';
import '../domain/pickup_location.dart';
import '../domain/service_area.dart';

/// Owns the "From" half of the One-Way route step: the starting point, filled
/// from GPS on open so the customer only has to type a destination.
///
/// A failed or out-of-area fix isn't an error screen — [start] stays null and
/// the view asks the customer to choose a starting point instead. Talks only
/// to [LocationRepository], per the MVVM guideline.
class TripStartViewModel extends ChangeNotifier {
  /// [initialStart] is a seam for previews/tests to render a filled row
  /// without a GPS round-trip; [locate] is then a no-op.
  TripStartViewModel({required this._repository, PickupLocation? initialStart})
    : _start = initialStart;

  final LocationRepository _repository;
  bool _disposed = false;

  PickupLocation? _start;

  /// The chosen starting point; null while locating or when GPS couldn't give
  /// a usable one.
  PickupLocation? get start => _start;

  bool _isLocating = false;
  bool get isLocating => _isLocating;

  /// Why the GPS fix wasn't used (permission refused, outside the served
  /// area…). Cleared once the customer picks a start themselves.
  String? _error;
  String? get error => _error;

  /// Whether the current [start] came from GPS rather than a manual pick.
  bool _isCurrentLocation = false;
  bool get isCurrentLocation => _isCurrentLocation;

  Future<PickupLocation?>? _locating;

  /// Fills [start] from the device location. Safe to call repeatedly: a fix
  /// already in flight is shared, and a start already set is kept.
  Future<PickupLocation?> locate() {
    if (_start != null) return Future.value(_start);
    return _locating ??= _locate();
  }

  Future<PickupLocation?> _locate() async {
    _isLocating = true;
    _error = null;
    _notify();
    try {
      final here = await _repository.currentLocation();
      // A manual pick may have landed while GPS was resolving — it wins.
      if (_start != null) return _start;
      if (!ServiceArea.contains(here.point)) {
        _error = ServiceArea.outsideMessage;
        return null;
      }
      _start = here;
      _isCurrentLocation = true;
      return here;
    } on LocationException catch (e) {
      _error = e.message;
      return _start;
    } finally {
      _isLocating = false;
      _locating = null;
      _notify();
    }
  }

  /// Adopts a starting point the customer chose (already area-checked by the
  /// picker that produced it).
  void setStart(PickupLocation location) {
    _start = location;
    _isCurrentLocation = false;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
