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
///
/// The window also opens with the clock, not only with the list: while the
/// driver holds a ride that isn't trackable yet, the rides are re-checked
/// every [recheckEvery], so sharing starts at T-60 min with nothing else
/// reloading the list.
class LocationShareViewModel extends ChangeNotifier {
  LocationShareViewModel({
    required this._myRides,
    required this._location,
    required this._repository,
    this._now = DateTime.now,
    this._minSendGap = const Duration(seconds: 10),
    this.recheckEvery = const Duration(seconds: 30),
    this.rideCheckEvery = const Duration(minutes: 2),
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

  /// How often the window is re-checked while a held ride is still ahead
  /// of it.
  final Duration recheckEvery;

  /// How often the driver's rides are re-read while sharing. A ride the
  /// customer cancelled while the app was in the background only reached
  /// the tray as a push; without this the location service, and its wake
  /// lock, would run on until the driver opened the app.
  final Duration rideCheckEvery;

  StreamSubscription<DeviceFix>? _subscription;
  Timer? _recheck;
  DateTime? _lastSentAt;
  DateTime? _lastRideCheck;
  bool _isSharing = false;
  bool _disposed = false;

  /// True while a ride is in its tracking window and the position stream
  /// is open. Drives the "Sharing your live location" note on the ride
  /// detail screen.
  bool get isSharing => _isSharing;

  void _onRidesChanged() {
    if (_disposed) return;
    final tracked = _myRides.trackableAt(_now()).isNotEmpty;
    if (tracked && _subscription == null) {
      _start();
    } else if (!tracked && _subscription != null) {
      _stop();
    }
    // Waiting on the clock: a ride is held but its window hasn't opened.
    final waiting = !tracked && _myRides.upcoming.isNotEmpty;
    if (waiting && _recheck == null) {
      _recheck = Timer.periodic(recheckEvery, (_) => _onRidesChanged());
    } else if (!waiting) {
      _recheck?.cancel();
      _recheck = null;
    }
  }

  void _start() {
    _subscription = _location.positionStream().listen(
      _onFix,
      onError: (_) {},
      cancelOnError: false,
    );
    _isSharing = true;
    _lastRideCheck = _now(); // the rides were just read
    _notify();
  }

  Future<void> _onFix(DeviceFix fix) async {
    final now = _now();
    final last = _lastSentAt;
    if (last != null && now.difference(last) < _minSendGap) {
      return; // Throttled — the OS can fire faster than every ~10s.
    }
    _lastSentAt = now;
    final checked = _lastRideCheck;
    if (checked != null && now.difference(checked) >= rideCheckEvery) {
      _lastRideCheck = now;
      // Stops sharing (via _onRidesChanged) once no ride needs it.
      unawaited(_myRides.load());
    }
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
    _lastRideCheck = null;
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
    _recheck?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
