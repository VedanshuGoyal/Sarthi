import 'package:flutter/foundation.dart';

import '../domain/multi_stop_trip.dart';
import '../domain/pickup_location.dart';
import '../domain/scheduling.dart' as scheduling;
import '../domain/trip_stop.dart';

/// One stop while the customer is still filling it in: every field optional
/// until it graduates into a [TripStop].
///
/// [id] is a stable identity that survives reordering, so the view can key
/// widgets and text controllers by it rather than by list position.
@immutable
class StopDraft {
  const StopDraft({
    required this.id,
    this.location,
    this.task = '',
    this.departBy,
  });

  final int id;
  final PickupLocation? location;
  final String task;
  final DateTime? departBy;

  /// True once every field is filled — the draft can become a [TripStop].
  bool get isComplete =>
      location != null && task.trim().isNotEmpty && departBy != null;

  StopDraft copyWith({
    PickupLocation? location,
    String? task,
    DateTime? departBy,
  }) => StopDraft(
    id: id,
    location: location ?? this.location,
    task: task ?? this.task,
    departBy: departBy ?? this.departBy,
  );
}

/// Drives the Multi-Stop trip planner: a start time plus an ordered task list
/// of stops the customer writes for the driver.
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient plan for a
/// single [start] location — the stop drafts and their ordering — and exposes
/// command methods the view calls. It holds no business logic beyond form
/// validation and never touches widgets, the network, or storage.
class MultiStopPlannerViewModel extends ChangeNotifier {
  /// [start] is the confirmed starting point from the previous step. The
  /// `initial*` seams let previews and tests start in a given state without
  /// tapping through the UI; production begins with one blank stop.
  MultiStopPlannerViewModel({
    required this.start,
    DateTime? initialScheduledAt,
    List<StopDraft>? initialStops,
  }) : _scheduledAt = initialScheduledAt ?? scheduling.defaultScheduledAt(),
       _stops = [...?initialStops] {
    if (_stops.isEmpty) _stops.add(const StopDraft(id: 0));
    _nextId = _stops.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  final PickupLocation start;

  /// A plan needs at least one errand, and stays a day plan — not a route
  /// sheet — by capping how many stops one driver is handed.
  static const int minStops = 1;
  static const int maxStops = 8;

  late int _nextId;

  DateTime _scheduledAt;
  DateTime get scheduledAt => _scheduledAt;

  final List<StopDraft> _stops;
  List<StopDraft> get stops => List.unmodifiable(_stops);

  bool get canAddStop => _stops.length < maxStops;
  bool get canRemoveStop => _stops.length > minStops;

  /// Sets when the driver should be at [start] to begin the plan.
  void setScheduledAt(DateTime when) {
    if (_scheduledAt == when) return;
    _scheduledAt = when;
    notifyListeners();
  }

  /// Appends a blank stop for the customer to fill in.
  void addStop() {
    if (!canAddStop) return;
    _stops.add(StopDraft(id: _nextId++));
    notifyListeners();
  }

  /// Removes the stop with [id]; the last remaining stop can't be removed.
  void removeStop(int id) {
    if (!canRemoveStop) return;
    final index = _indexOf(id);
    if (index == -1) return;
    _stops.removeAt(index);
    notifyListeners();
  }

  /// Swaps the stop with [id] one place earlier/later in the visiting order.
  void moveStopUp(int id) => _swap(_indexOf(id), -1);
  void moveStopDown(int id) => _swap(_indexOf(id), 1);

  void setStopLocation(int id, PickupLocation location) =>
      _update(id, (stop) => stop.copyWith(location: location));

  void setStopTask(int id, String task) =>
      _update(id, (stop) => stop.copyWith(task: task));

  void setStopDepartBy(int id, DateTime when) =>
      _update(id, (stop) => stop.copyWith(departBy: when));

  int _indexOf(int id) => _stops.indexWhere((stop) => stop.id == id);

  void _swap(int index, int delta) {
    final other = index + delta;
    if (index == -1 || other < 0 || other >= _stops.length) return;
    final moved = _stops[index];
    _stops[index] = _stops[other];
    _stops[other] = moved;
    notifyListeners();
  }

  void _update(int id, StopDraft Function(StopDraft) change) {
    final index = _indexOf(id);
    if (index == -1) return;
    final changed = change(_stops[index]);
    final current = _stops[index];
    if (changed.location == current.location &&
        changed.task == current.task &&
        changed.departBy == current.departBy) {
      return; // No-op so we don't churn listeners.
    }
    _stops[index] = changed;
    notifyListeners();
  }

  /// Why the stop with [id] can't keep its leave-by time, or null when it fits
  /// the timeline. Times must run forward: each stop's deadline comes after the
  /// previous timed stop's (or after the trip start, for the first).
  ///
  /// Untimed stops are skipped rather than flagged — completeness is
  /// [StopDraft.isComplete]'s job; this only polices ordering.
  String? timeErrorFor(int id) => _timeErrors[id];

  Map<int, String> get _timeErrors {
    final errors = <int, String>{};
    var lastAt = _scheduledAt;
    var lastLabel = 'the start time';
    for (final (i, stop) in _stops.indexed) {
      final departBy = stop.departBy;
      if (departBy == null) continue;
      if (!departBy.isAfter(lastAt)) {
        errors[stop.id] = 'Leave-by must be after $lastLabel.';
      } else {
        lastAt = departBy;
        lastLabel = 'stop ${i + 1}';
      }
    }
    return errors;
  }

  /// When the plan wraps up — the last timed stop's deadline, or null until at
  /// least one stop has a time. Shown as "wraps up by …" in the summary.
  DateTime? get endsAt {
    DateTime? last;
    for (final stop in _stops) {
      final departBy = stop.departBy;
      if (departBy != null && (last == null || departBy.isAfter(last))) {
        last = departBy;
      }
    }
    return last;
  }

  /// True once every stop is complete and the timeline runs forward — gates
  /// the CTA.
  bool get canConfirm =>
      _stops.every((stop) => stop.isComplete) && _timeErrors.isEmpty;

  /// The assembled trip, or null until [canConfirm].
  MultiStopTrip? get trip => canConfirm
      ? MultiStopTrip(
          start: start,
          scheduledAt: _scheduledAt,
          stops: [
            for (final stop in _stops)
              TripStop(
                location: stop.location!,
                task: stop.task.trim(),
                departBy: stop.departBy!,
              ),
          ],
        )
      : null;
}
