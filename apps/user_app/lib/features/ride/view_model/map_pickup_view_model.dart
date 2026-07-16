import 'package:flutter/foundation.dart';

import '../data/location_repository.dart';
import '../domain/geo_point.dart';
import '../domain/pickup_location.dart';

/// Drives the "pin your spot on the map" step.
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient map state
/// (where the map is centred, the address resolved for that centre, spinners,
/// any error) and exposes command methods the view calls as the camera moves.
/// It talks only to [LocationRepository] — never to the maps plugin or GPS —
/// and never sees a `LatLng`: the view converts to/from [GeoPoint] at the
/// boundary so no map-SDK type leaks past the data layer.
class MapPickupViewModel extends ChangeNotifier {
  /// [initialCenter] seeds the camera before the device fix arrives;
  /// [initialResolved] is a seam so previews/tests can render the "address
  /// found" state directly.
  MapPickupViewModel({
    required this._repository,
    GeoPoint initialCenter = defaultCenter,
    PickupLocation? initialResolved,
  }) : _center = initialCenter,
       _initialCenter = initialCenter,
       _resolved = initialResolved;

  final LocationRepository _repository;

  /// Fallback camera target when the device location is unknown or refused —
  /// a country-level view of India, matching the service area.
  static const GeoPoint defaultCenter = GeoPoint(
    latitude: 22.5937,
    longitude: 78.9629,
  );

  /// Guards against out-of-order reverse-geocodes: only the newest resolve may
  /// write, so a slow earlier request can't clobber a faster later one.
  int _resolveSeq = 0;
  bool _disposed = false;

  GeoPoint _initialCenter;

  /// Where the camera should start. Fixed once [init] picks the device fix (or
  /// the fallback), since the map reads it only at creation.
  GeoPoint get initialCenter => _initialCenter;

  bool _isReady = false;

  /// True once an initial camera target has been chosen — the view shows a
  /// spinner until then rather than flashing the fallback view.
  bool get isReady => _isReady;

  GeoPoint _center;

  /// The map's current centre — the point that will be pinned on confirm.
  GeoPoint get center => _center;

  bool _isMoving = false;

  /// True while the user is actively panning; the pin has no resolved address
  /// yet, so the confirm CTA is disabled.
  bool get isMoving => _isMoving;

  bool _isResolving = false;

  /// True while a reverse-geocode for the settled centre is in flight.
  bool get isResolving => _isResolving;

  PickupLocation? _resolved;

  /// The pickup for the current centre, once its address is known.
  PickupLocation? get resolved => _resolved;

  String? _error;
  String? get error => _error;

  /// The address to show under the pin: the resolved street address, or the
  /// raw coordinates while we wait / if geocoding had nothing.
  String get pinLabel => _resolved?.address ?? _center.toLatLngParam();

  /// True once the centre has a confirmable pickup and isn't mid-pan.
  bool get canConfirm => _resolved != null && !_isMoving;

  /// Chooses the opening camera target: the device's current spot when we can
  /// read it, else the fallback. Then resolves that centre's address so the
  /// card isn't empty on first paint.
  Future<void> init() async {
    try {
      final point = await _repository.currentPoint();
      _initialCenter = point;
      _center = point;
    } on LocationException {
      // GPS off/refused: keep the fallback centre. Not surfaced as an error —
      // the user can still pan to their spot.
    } finally {
      _isReady = true;
      _notify();
    }
    await _resolve(_center);
  }

  /// The user started panning: drop the stale address so the CTA disables and
  /// the card shows a "moving" state. Cheap — fired once per gesture, not per
  /// frame — so later [onCameraMove] calls only track the centre.
  void onCameraMove(GeoPoint target) {
    _center = target;
    if (_isMoving) return;
    _isMoving = true;
    _resolved = null;
    _error = null;
    _notify();
  }

  /// The camera settled: resolve the address for wherever it landed.
  Future<void> onCameraIdle() async {
    _isMoving = false;
    await _resolve(_center);
  }

  /// Re-reads the device location for the "locate me" button and returns it so
  /// the view can animate the camera there; the ensuing camera-idle resolves
  /// the address. Returns null (and sets [error]) when GPS is unavailable.
  Future<GeoPoint?> locateMe() async {
    _error = null;
    try {
      final point = await _repository.currentPoint();
      _center = point;
      return point;
    } on LocationException catch (e) {
      _error = e.message;
      _notify();
      return null;
    }
  }

  Future<void> _resolve(GeoPoint point) async {
    final seq = ++_resolveSeq;
    _isResolving = true;
    _notify();
    try {
      final pickup = await _repository.reverseGeocode(point);
      if (seq != _resolveSeq) return; // superseded by a newer settle
      _resolved = pickup;
      _error = null;
    } on LocationException catch (e) {
      if (seq != _resolveSeq) return;
      _resolved = null;
      _error = e.message;
    } finally {
      if (seq == _resolveSeq) {
        _isResolving = false;
        _notify();
      }
    }
  }

  /// Notifies only while mounted. This view model is `autoDispose`, so an
  /// in-flight geocode can complete after the screen — and this notifier — is
  /// gone; notifying then would throw.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
