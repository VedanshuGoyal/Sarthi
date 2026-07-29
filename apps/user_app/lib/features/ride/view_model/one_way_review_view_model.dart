import 'package:flutter/foundation.dart';

import '../data/location_repository.dart';
import '../domain/one_way_trip.dart';
import '../domain/scheduling.dart' as scheduling;

/// Drives the One-Way review step: the estimated drive time for the choices
/// made on the details step, and the final confirmation.
///
/// A [ChangeNotifier] per the MVVM guideline, owning the state for a fixed
/// [draft]. The schedule and car are settled by the time this screen exists,
/// so exactly one drive-time request is made — on construction, for the chosen
/// departure — instead of one per nudge of the time picker. To keep API costs
/// down, near-term departures (within `scheduling.nearTermDepartureWindow`)
/// use the cheap current-traffic estimate, while far-out ones use the costlier
/// time-aware call. The customer never chooses a duration: the estimate *is*
/// the trip's duration, and the booking can't be confirmed without one.
class OneWayReviewViewModel extends ChangeNotifier {
  /// [draft] is the route + schedule + car settled on the previous step.
  /// [repository] supplies the drive-time estimate; when null (or when
  /// [initialTravelTime] is given) no estimate is fetched — a seam for
  /// previews and tests. [now] is the clock used to classify the departure as
  /// near-term — a seam for tests.
  OneWayReviewViewModel({
    required this.draft,
    LocationRepository? repository,
    Duration? initialTravelTime,
    DateTime Function()? now,
  }) : _repository = repository,
       _now = now ?? DateTime.now,
       _travelTime = initialTravelTime {
    if (initialTravelTime == null && repository != null) {
      _estimateTravelTime();
    }
  }

  final OneWayDraft draft;
  final LocationRepository? _repository;
  final DateTime Function() _now;

  Duration? _travelTime;

  /// The estimated driving time for the route at the chosen start time, once
  /// the request resolves; null while loading or when the estimate failed.
  Duration? get travelTime => _travelTime;

  bool _isEstimatingTravelTime = false;

  /// True while the drive-time request is in flight.
  bool get isEstimatingTravelTime => _isEstimatingTravelTime;

  /// True when the last drive-time request failed — the view offers a retry.
  bool get estimateFailed =>
      _travelTime == null && !_isEstimatingTravelTime && _repository != null;

  /// Re-asks for the drive time after a failure.
  void retryEstimate() {
    if (_repository == null || _isEstimatingTravelTime) return;
    _estimateTravelTime();
  }

  /// True once the estimate has arrived — gates the CTA. Every customer
  /// choice was already made on the details step; the drive time is the one
  /// missing piece (it is the trip's duration).
  bool get canConfirm => _travelTime != null;

  /// The assembled request, or null until [canConfirm].
  OneWayTrip? get trip => canConfirm
      ? OneWayTrip(
          start: draft.start,
          destination: draft.destination,
          scheduledAt: draft.scheduledAt,
          estimatedTravelTime: _travelTime!,
          car: draft.car,
        )
      : null;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Asks the repository how long the drive takes when departing at the
  /// draft's start time — the cheap current-traffic call for near-term
  /// departures, the time-aware one otherwise. While the request is in flight
  /// (and after a failure) the estimate is null, which keeps the booking
  /// unconfirmable — the duration comes from this estimate, so there is
  /// nothing to book without it.
  Future<void> _estimateTravelTime() async {
    final nearTerm = scheduling.isNearTermDeparture(draft.scheduledAt, _now());
    _isEstimatingTravelTime = true;
    _travelTime = null;
    notifyListeners();

    Duration? eta;
    try {
      eta = await _repository!.travelTime(
        start: draft.start.point,
        destination: draft.destination.point,
        departureAt: nearTerm ? null : draft.scheduledAt,
      );
    } catch (_) {
      eta = null;
    }

    if (_disposed) return;
    _travelTime = eta;
    _isEstimatingTravelTime = false;
    notifyListeners();
  }
}
