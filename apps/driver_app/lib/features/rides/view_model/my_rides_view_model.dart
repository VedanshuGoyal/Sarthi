import 'package:flutter/foundation.dart';

import '../../../core/refresh_throttle.dart';
import '../../../l10n/l10n.dart';
import '../data/rides_repository.dart';
import '../domain/ride.dart';

/// The driver's own rides, split into the Rides panel's three tabs, plus the
/// step-by-step actions on one ride (arrive → start → complete, or release).
///
/// The backend is the source of truth: every action answers with the ride's
/// new state, which replaces the local copy rather than being guessed at.
class MyRidesViewModel extends ChangeNotifier {
  MyRidesViewModel({required this._repository, this._onCompleted, Clock? now})
    : _fetched = RefreshThrottle(now: now);

  final RidesRepository _repository;
  final RefreshThrottle _fetched;

  /// Called when one of the driver's rides finishes with money in it, so
  /// earnings can refresh: completed here, or found on a reload to have
  /// finished underneath — the customer ended the trip early, or cancelled
  /// at the pickup with a fee.
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

  /// Re-reads the driver's rides. Only the latest load's answer is used,
  /// and rides changed on this phone while it was in flight (an action's
  /// reply, an accept, a release) keep their newer state: the list the
  /// server sent may predate them.
  ///
  /// A ride that was underway and comes back finished with money in it
  /// (see [_onCompleted]) refreshes earnings.
  Future<void> load() async {
    final seq = ++_loadSeq;
    _fetched.mark();
    _isLoading = true;
    _notify();
    try {
      final fetched = await _repository.myRides();
      if (seq != _loadSeq) return;
      final edits = _editsDuringLoad;
      final fetchedIds = {for (final r in fetched) r.id};
      final next = [
        for (final r in fetched)
          if (!edits.containsKey(r.id)) r else ?edits[r.id],
        for (final MapEntry(:key, :value) in edits.entries)
          if (!fetchedIds.contains(key)) ?value,
      ];
      final finished = _finishedWithMoney(_rides, next);
      _rides = next;
      _error = null;
      if (finished && !_disposed) _onCompleted?.call();
    } on RidesException catch (e) {
      if (seq == _loadSeq) _error = e.message;
    } finally {
      if (seq == _loadSeq) {
        _editsDuringLoad.clear();
        _isLoading = false;
        _hasLoaded = true;
        _notify();
      }
    }
  }

  /// Re-reads the rides unless they were read within the last
  /// [RefreshThrottle.defaultGap] or a read is in flight — for the app
  /// coming back to the foreground, where pushes that arrived meanwhile only
  /// reached the tray.
  Future<void> refreshIfStale() async {
    if (_isLoading || !_fetched.isStale) return;
    await load();
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
    if (_isLoading) _editsDuringLoad[ride.id] = merged;
    _notify();
  }

  int _loadSeq = 0;

  /// Rides changed on this phone while a load was in flight — null for one
  /// handed back. They win over that load's possibly older copy.
  final Map<String, Ride?> _editsDuringLoad = {};

  bool _disposed = false;

  /// Notifies only while alive: a different driver signing in replaces this
  /// view model while a load or action may still be in flight.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
    _notify();
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
        if (_isLoading) _editsDuringLoad[ride.id] = null;
      } else if (updated != null) {
        upsert(updated);
      }
      if (action == RideAction.complete) _onCompleted?.call();
      return null;
    } on RidesException catch (e) {
      if (e.code == 'ride_state') {
        await load();
        // The step had already happened — an earlier tap went through but
        // its reply was lost — so there's nothing to report.
        // (A completion found this way has refreshed earnings in [load].)
        final reached = _reachedBy[action];
        if (reached != null && byId(ride.id)?.status == reached) {
          return null;
        }
      }
      if (action == RideAction.rate) {
        return switch (e.code) {
          'invalid_rating' => L10n.current.myRidesInvalidRating,
          'ride_state' => L10n.current.myRidesCantRate,
          _ => e.message,
        };
      }
      return e.message;
    } finally {
      _busyRideId = null;
      _notify();
    }
  }

  /// The status each step moves a ride to.
  static const Map<RideAction, RideStatus> _reachedBy = {
    RideAction.arrive: RideStatus.arrived,
    RideAction.start: RideStatus.inProgress,
    RideAction.complete: RideStatus.completed,
    RideAction.noShow: RideStatus.cancelled,
  };

  /// Whether a ride underway in [before] is, in [after], completed or
  /// cancelled with a fee — money the earnings summary now counts.
  static bool _finishedWithMoney(List<Ride> before, List<Ride> after) {
    final underway = {
      for (final r in before)
        if (r.status.isActive) r.id,
    };
    return after.any(
      (r) =>
          underway.contains(r.id) &&
          (r.status == RideStatus.completed || r.hasCancellationFee),
    );
  }

  static List<Ride> _sorted(Iterable<Ride> rides, Comparator<Ride> compare) =>
      rides.toList()..sort(compare);
}
