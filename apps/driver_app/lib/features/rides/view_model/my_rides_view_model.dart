import 'package:flutter/foundation.dart';

import '../data/rides_repository.dart';
import '../domain/ride.dart';

/// The driver's own rides, split into the Rides panel's three tabs, plus the
/// step-by-step actions on one ride (arrive → start → complete, or release).
///
/// The backend is the source of truth: every action answers with the ride's
/// new state, which replaces the local copy rather than being guessed at.
class MyRidesViewModel extends ChangeNotifier {
  MyRidesViewModel({required this._repository, this._onCompleted});

  final RidesRepository _repository;

  /// Called after a ride is completed, so earnings can refresh.
  final VoidCallback? _onCompleted;

  List<Ride> _rides = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;
  String? _busyRideId;

  bool get isLoading => _isLoading;

  /// False until the first load finishes, so panels can show a skeleton
  /// instead of an empty state.
  bool get hasLoaded => _hasLoaded;

  /// The last load failure, safe to show.
  String? get error => _error;

  /// The ride an action is in flight for, so its buttons can show progress.
  String? get busyRideId => _busyRideId;

  /// Accepted rides the driver hasn't reached yet, soonest first.
  List<Ride> get upcoming => _sorted(
    _rides.where((r) => r.status == RideStatus.accepted),
    (a, b) => a.scheduledAt.compareTo(b.scheduledAt),
  );

  /// Rides the driver is at or on, soonest first.
  List<Ride> get ongoing => _sorted(
    _rides.where(
      (r) =>
          r.status == RideStatus.arrived || r.status == RideStatus.inProgress,
    ),
    (a, b) => a.scheduledAt.compareTo(b.scheduledAt),
  );

  /// Finished rides, most recently completed first.
  List<Ride> get completed => _sorted(
    _rides.where((r) => r.status == RideStatus.completed),
    (a, b) => (b.completedAt ?? b.scheduledAt).compareTo(
      a.completedAt ?? a.scheduledAt,
    ),
  );

  /// Rides a customer cancelled after the driver took them, most recently
  /// cancelled first.
  List<Ride> get cancelled => _sorted(
    _rides.where((r) => r.status == RideStatus.cancelled),
    (a, b) => (b.cancelledAt ?? b.scheduledAt).compareTo(
      a.cancelledAt ?? a.scheduledAt,
    ),
  );

  /// Rides still in the live-tracking window at [now] — the driver holds
  /// them and the pickup is at most 60 minutes out. Backs
  /// [LocationShareViewModel].
  List<Ride> trackableAt(DateTime now) =>
      [...upcoming, ...ongoing].where((r) => r.isTrackableAt(now)).toList();

  /// The ride that needs the driver next: one underway, else the soonest
  /// upcoming one.
  Ride? get current => ongoing.firstOrNull ?? upcoming.firstOrNull;

  /// The latest copy of ride [id], if it is one of the driver's.
  Ride? byId(String id) => _rides.where((r) => r.id == id).firstOrNull;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _rides = await _repository.myRides();
      _error = null;
    } on RidesException catch (e) {
      _error = e.message;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Adds or replaces [ride] — e.g. one just accepted from the requests feed.
  void upsert(Ride ride) {
    final existing = byId(ride.id);
    final merged = existing == null ? ride : existing.mergedWith(ride);
    _rides = [
      for (final r in _rides)
        if (r.id != ride.id) r,
      merged,
    ];
    notifyListeners();
  }

  /// Applies a lifecycle [action] to [ride]. Returns null on success or a
  /// message to show. A ride that has moved on server-side (another device,
  /// a stale screen) is reloaded so the panel shows where it really is.
  ///
  /// Starting needs [otp], the code from the customer's app. Rating needs
  /// [stars] (1–5) and takes an optional [note].
  Future<String?> act(
    Ride ride,
    RideAction action, {
    String? otp,
    int? stars,
    String? note,
  }) async {
    _busyRideId = ride.id;
    notifyListeners();
    try {
      final updated = await _repository.act(
        ride.id,
        action,
        otp: otp,
        stars: stars,
        note: note,
      );
      if (action == RideAction.release) {
        _rides = [
          for (final r in _rides)
            if (r.id != ride.id) r,
        ];
      } else if (updated != null) {
        upsert(updated);
      }
      if (action == RideAction.complete) _onCompleted?.call();
      return null;
    } on RidesException catch (e) {
      if (e.code == 'ride_state') await load();
      if (action == RideAction.rate) {
        return switch (e.code) {
          'invalid_rating' => 'Pick 1 to 5 stars for the customer.',
          'ride_state' => "This ride can't be rated right now.",
          _ => e.message,
        };
      }
      return e.message;
    } finally {
      _busyRideId = null;
      notifyListeners();
    }
  }

  static List<Ride> _sorted(Iterable<Ride> rides, Comparator<Ride> compare) =>
      rides.toList()..sort(compare);
}
