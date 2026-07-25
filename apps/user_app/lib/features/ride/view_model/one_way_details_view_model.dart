import 'package:flutter/foundation.dart';

import '../domain/car_type.dart';
import '../domain/one_way_trip.dart';
import '../domain/pickup_location.dart';
import '../domain/scheduling.dart' as scheduling;
import '../domain/transmission.dart';

/// Drives the One-Way "trip details" step (when the trip starts, which car).
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient form state
/// for a fixed [route] and exposes command methods the view calls. This step
/// deliberately makes no drive-time request — the customer settles the start
/// time and car freely here, and only the review step that follows spends an
/// API call, once, on the departure they actually chose. The step is done when
/// a car type is picked; [draft] then carries the choices forward.
class OneWayDetailsViewModel extends ChangeNotifier {
  /// [route] is the start/destination pair from the previous steps. The
  /// `initial*` seams let previews and tests start in a given state without
  /// tapping through the UI; production starts with the defaults.
  OneWayDetailsViewModel({
    required this.route,
    DateTime? initialScheduledAt,
    CarType? initialCarType,
    Transmission initialTransmission = Transmission.automatic,
  }) : _scheduledAt = initialScheduledAt ?? scheduling.defaultScheduledAt(),
       _carType = initialCarType,
       _transmission = initialTransmission;

  final OneWayRoute route;

  PickupLocation get start => route.start;
  PickupLocation get destination => route.destination;

  DateTime _scheduledAt;
  DateTime get scheduledAt => _scheduledAt;

  /// Sets when the trip should start (date and time already combined).
  void setScheduledAt(DateTime when) {
    if (_scheduledAt == when) return;
    _scheduledAt = when;
    notifyListeners();
  }

  CarType? _carType;
  CarType? get carType => _carType;

  void selectCarType(CarType type) {
    if (_carType == type) return;
    _carType = type;
    notifyListeners();
  }

  Transmission _transmission;
  Transmission get transmission => _transmission;

  void selectTransmission(Transmission value) {
    if (_transmission == value) return;
    _transmission = value;
    notifyListeners();
  }

  /// True once every required choice is made — gates the CTA. The start time
  /// and transmission always have a value, so only a car type must be chosen.
  bool get canContinue => _carType != null;

  /// The choices to hand to the review step, or null until [canContinue].
  OneWayDraft? get draft => canContinue
      ? (
          start: start,
          destination: destination,
          scheduledAt: _scheduledAt,
          carType: _carType!,
          transmission: _transmission,
        )
      : null;
}
