import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/refresh_throttle.dart';
import '../../../core/services/location_service.dart';
import '../data/rides_repository.dart';
import '../domain/ride.dart';

/// The Home panel's state: whether the driver is on duty, and the open ride
/// requests near them while they are.
///
/// Rides are booked ahead, so there is no one-driver dispatch — while online
/// the feed refreshes every [pollEvery], each time re-reporting the driver's
/// position (which keeps them in the backend's live presence index, and so
/// in line for "New ride request" pushes) and re-reading what's open near
/// them. A push arriving while the app is open refreshes it straight away.
/// Offline, it stops polling and clears.
class DutyViewModel extends ChangeNotifier {
  DutyViewModel({
    required this._repository,
    required this._location,
    this._onAccepted,
    this.pollEvery = const Duration(seconds: 20),
    Clock? now,
  }) : _fetched = RefreshThrottle(now: now);

  final RidesRepository _repository;
  final RefreshThrottle _fetched;
  final LocationService _location;

  /// Hands an accepted ride to the driver's own rides list.
  final void Function(Ride accepted)? _onAccepted;

  /// How often the requests feed refreshes while online.
  final Duration pollEvery;

  bool _isOnline = false;
  bool _isSwitching = false;
  bool _isLoading = false;
  String? _error;
  List<Ride> _requests = const [];
  final Set<String> _busy = {};
  DevicePosition? _position;
  Timer? _timer;
  bool _disposed = false;

  bool get isOnline => _isOnline;

  /// True while going online/offline is in flight.
  bool get isSwitching => _isSwitching;

  /// True while the feed is refreshing.
  bool get isLoading => _isLoading;

  /// The last failure, safe to show.
  String? get error => _error;

  /// Open rides the driver can take, soonest first.
  List<Ride> get requests => _requests;

  /// Whether we have the driver's position (so distances are shown).
  bool get hasPosition => _position != null;

  /// Whether an accept/decline is in flight for [rideId].
  bool isBusy(String rideId) => _busy.contains(rideId);

  /// Goes on or off duty.
  Future<void> setOnline(bool online) async {
    if (online == _isOnline || _isSwitching) return;
    _isSwitching = true;
    _error = null;
    _notify();
    try {
      if (online) {
        _position = await _location.currentPosition();
        // Signed out while locating: this view model is gone, and nothing
        // would ever cancel a poll started now.
        if (_disposed) return;
        await _repository.setDuty(
          online: true,
          lat: _position?.lat,
          lng: _position?.lng,
        );
        if (_disposed) return;
        _isOnline = true;
        _timer = Timer.periodic(pollEvery, (_) => refresh(locate: true));
        await refresh();
      } else {
        _timer?.cancel();
        _timer = null;
        _isOnline = false;
        _requests = const [];
        // Best-effort: being offline locally is what matters to the driver.
        await _repository.setDuty(online: false).catchError((_) {});
      }
    } on RidesException catch (e) {
      _error = e.message;
    } finally {
      _isSwitching = false;
      _notify();
    }
  }

  /// The backend took the driver off duty — their app hadn't checked in for
  /// hours (the `duty_off` push). Stops polling and shows them offline
  /// without telling the backend again; going on duty is theirs to do.
  void markOffDuty() {
    if (!_isOnline) return;
    _timer?.cancel();
    _timer = null;
    _isOnline = false;
    _requests = const [];
    _notify();
  }

  /// Re-reads the open requests. With [locate], refreshes the driver's
  /// position first and re-reports it to the backend.
  ///
  /// Going off duty while this is in flight wins: locating can take a few
  /// seconds, and re-reporting "online" after the driver went offline would
  /// put them back in line for ride pushes behind their back.
  Future<void> refresh({bool locate = false}) async {
    if (!_isOnline || _isLoading) return;
    _fetched.mark();
    _isLoading = true;
    _notify();
    try {
      if (locate) {
        _position = await _location.currentPosition() ?? _position;
        if (!_isOnline || _disposed) return;
        await _repository.setDuty(
          online: true,
          lat: _position?.lat,
          lng: _position?.lng,
        );
      }
      final requests = await _repository.requests(
        lat: _position?.lat,
        lng: _position?.lng,
      );
      if (!_isOnline) return;
      _requests = requests;
      _error = null;
    } on RidesException catch (e) {
      if (_isOnline) _error = e.message;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// For the app coming back to the foreground while on duty: re-locates,
  /// re-reports the driver and re-reads the feed — unless the poll (or a
  /// push) did within the last [RefreshThrottle.defaultGap]. In the
  /// background the poll may not have run at all (Android pauses a
  /// sleeping phone), so the feed and the driver's presence can be stale.
  Future<void> refreshIfStale() async {
    if (!_isOnline || _isLoading || !_fetched.isStale) return;
    await refresh(locate: true);
  }

  /// Takes [ride]. Returns null on success, or a message to show. A ride
  /// someone else got first, or that the customer cancelled in the
  /// meantime, is dropped from the feed — the backend's own message
  /// ("This ride is no longer available.") covers both.
  ///
  /// "No longer available" can also mean the driver already has it: an
  /// earlier tap went through but its reply was lost. So before saying the
  /// ride is gone, the driver's own rides are checked, and a ride they hold
  /// is handed over as accepted.
  Future<String?> accept(Ride ride) async {
    _busy.add(ride.id);
    _notify();
    try {
      final accepted = await _repository.act(ride.id, RideAction.accept);
      _remove(ride.id);
      if (accepted != null) _onAccepted?.call(accepted);
      return null;
    } on RidesException catch (e) {
      if (e.code == 'ride_unavailable' || e.code == 'ride_not_found') {
        _remove(ride.id);
      }
      if (e.code == 'ride_unavailable') {
        final held = await _heldRide(ride.id);
        if (held != null) {
          _onAccepted?.call(held);
          return null;
        }
      }
      return e.message;
    } finally {
      _busy.remove(ride.id);
      _notify();
    }
  }

  /// Ride [id] if the driver holds it — accepted, at the pickup or underway.
  Future<Ride?> _heldRide(String id) async {
    try {
      final mine = await _repository.myRides();
      return mine.where((r) => r.id == id && r.status.isActive).firstOrNull;
    } on RidesException {
      return null;
    }
  }

  /// Hides [ride] from the feed.
  Future<String?> decline(Ride ride) async {
    _busy.add(ride.id);
    _notify();
    try {
      await _repository.act(ride.id, RideAction.decline);
      _remove(ride.id);
      return null;
    } on RidesException catch (e) {
      return e.message;
    } finally {
      _busy.remove(ride.id);
      _notify();
    }
  }

  void _remove(String id) {
    _requests = [
      for (final r in _requests)
        if (r.id != id) r,
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
