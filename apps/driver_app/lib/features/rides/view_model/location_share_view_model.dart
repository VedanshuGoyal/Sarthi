import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/location_service.dart';
import '../data/rides_repository.dart';
import 'my_rides_view_model.dart';

/// Streams the driver's position to the backend (`PUT /driver/location`)
/// for as long as any of the driver's rides is inside its live-tracking
/// window (see `Ride.isTrackableAt`) — accepted, arrived or in_progress,
/// and the pickup within the next 60 minutes.
///
/// Watches [MyRidesViewModel] rather than owning a ride list of its own, so
/// it starts and stops on its own as a ride moves through
/// accepted → arrived → in_progress → completed — no screen has to drive
/// it, only create it once (the Home shell does, on sign-in). It's
/// independent of duty status: a ride stays trackable even if the driver
/// has gone off duty in between.
class LocationShareViewModel extends ChangeNotifier {
  LocationShareViewModel({
    required this._myRides,
    required this._location,
    required this._repository,
    this._now = DateTime.now,
    this._minSendGap = const Duration(seconds: 10),
  }) {
    _myRides.addListener(_onRidesChanged);
    _onRidesChanged();
  }

  final MyRidesViewModel _myRides;
  final LocationService _location;
  final RidesRepository _repository;

  /// The clock seam — overridden in tests so the tracking window can be
  /// exercised without waiting on real time.
  final DateTime Function() _now;

  /// Floor on how often a fix is actually sent, independent of how often
  /// the position stream fires.
  final Duration _minSendGap;

  StreamSubscription<DeviceFix>? _subscription;
  DateTime? _lastSentAt;
  bool _isSharing = false;
  bool _disposed = false;

  /// True while a ride is in its tracking window and the position stream
  /// is open. Drives the "Sharing your live location" note on the ride
  /// detail screen.
  bool get isSharing => _isSharing;

  void _onRidesChanged() {
    final tracked = _myRides.trackableAt(_now()).isNotEmpty;
    if (tracked && _subscription == null) {
      _start();
    } else if (!tracked && _subscription != null) {
      _stop();
    }
  }

  void _start() {
    _subscription = _location.positionStream().listen(
      _onFix,
      onError: (_) {},
      cancelOnError: false,
    );
    _isSharing = true;
    _notify();
  }

  Future<void> _onFix(DeviceFix fix) async {
    final now = _now();
    final last = _lastSentAt;
    if (last != null && now.difference(last) < _minSendGap) {
      return; // Throttled — the OS can fire faster than every ~10s.
    }
    _lastSentAt = now;
    try {
      await _repository.shareLocation(
        lat: fix.lat,
        lng: fix.lng,
        heading: fix.heading,
      );
    } catch (_) {
      // Best-effort: a dropped update isn't worth surfacing to the driver.
    }
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _lastSentAt = null;
    _isSharing = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _myRides.removeListener(_onRidesChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
