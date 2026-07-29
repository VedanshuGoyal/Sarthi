import 'package:flutter/foundation.dart';

import '../domain/car.dart';
import '../domain/one_way_trip.dart';
import '../domain/pickup_location.dart';
import '../domain/scheduling.dart' as scheduling;

/// Drives the One-Way "trip details" step (when the trip starts, which car).
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient form state
/// for a fixed [route] and exposes command methods the view calls. This step
/// deliberately makes no drive-time request — the customer settles the start
/// time and car freely here, and only the review step that follows spends an
/// API call, once, on the departure they actually chose. The step is done when
/// a saved car is picked; [draft] then carries the choices forward. The
/// saved-car *list* lives in the saved-cars view model; this one only holds
/// which car was picked.
class OneWayDetailsViewModel extends ChangeNotifier {
  /// [route] is the start/destination pair from the previous steps. The
  /// `initial*` seams let previews and tests start in a given state without
  /// tapping through the UI; production starts with the defaults.
  OneWayDetailsViewModel({
    required this.route,
    DateTime? initialScheduledAt,
    Car? initialCar,
  }) : _scheduledAt = initialScheduledAt ?? scheduling.defaultScheduledAt(),
       _car = initialCar;

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

  Car? _car;

  /// The saved car picked for this trip; null until the customer picks one.
  Car? get car => _car;

  void selectCar(Car car) {
    if (_car == car) return;
    _car = car;
    notifyListeners();
  }

  /// True once every required choice is made — gates the CTA. The start time
  /// always has a value, so only a car must be chosen.
  bool get canContinue => _car != null;

  /// The choices to hand to the review step, or null until [canContinue].
  OneWayDraft? get draft => canContinue
      ? (
          start: start,
          destination: destination,
          scheduledAt: _scheduledAt,
          car: _car!,
        )
      : null;
}
