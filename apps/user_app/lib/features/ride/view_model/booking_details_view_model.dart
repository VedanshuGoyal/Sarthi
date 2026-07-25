import 'package:flutter/foundation.dart';

import '../domain/car_type.dart';
import '../domain/pickup_location.dart';
import '../domain/round_trip_booking.dart';
import '../domain/round_trip_fare.dart';
import '../domain/scheduling.dart' as scheduling;
import '../domain/transmission.dart';

/// Drives Round Trip's "booking details" step (hours, schedule, car, gearbox).
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient form state
/// for a single [pickup] and exposes command methods the view calls. It holds
/// no business logic and never touches widgets, the network, or storage.
class BookingDetailsViewModel extends ChangeNotifier {
  /// [pickup] is the confirmed location from the previous step. The `initial*`
  /// seams let previews and tests start in a given state without tapping
  /// through the UI; production starts with the defaults.
  BookingDetailsViewModel({
    required this.pickup,
    int initialHours = 2,
    DateTime? initialScheduledAt,
    CarType? initialCarType,
    Transmission initialTransmission = Transmission.automatic,
  }) : _hours = initialHours.clamp(minHours, maxHours),
       _scheduledAt = initialScheduledAt ?? defaultScheduledAt(),
       _carType = initialCarType,
       _transmission = initialTransmission;

  final PickupLocation pickup;

  /// Bounds on how long a driver can be hired for in one Round Trip.
  static const int minHours = 1;
  static const int maxHours = 12;

  /// One-tap durations offered alongside the stepper.
  static const List<int> quickHours = [1, 2, 4, 6, 8, 10];

  /// The pre-filled start time — the shared "one hour out, quarter-hour
  /// rounded" policy from `domain/scheduling.dart`.
  static DateTime defaultScheduledAt([DateTime? now]) =>
      scheduling.defaultScheduledAt(now);

  int _hours;
  int get hours => _hours;

  DateTime _scheduledAt;
  DateTime get scheduledAt => _scheduledAt;

  CarType? _carType;
  CarType? get carType => _carType;

  Transmission _transmission;
  Transmission get transmission => _transmission;

  bool get canDecrementHours => _hours > minHours;
  bool get canIncrementHours => _hours < maxHours;

  /// The tariff for the current selection. Until a car type is picked we preview
  /// the standard rate; choosing luxury re-prices at the premium rate.
  RoundTripTariff get _tariff => _carType == null
      ? RoundTripTariff.standard
      : RoundTripTariff.forCarType(_carType!);

  /// The base fare (whole rupees) for the current [hours] under the applicable
  /// tariff, before any late-night surcharge.
  int get baseFare => _tariff.fareFor(_hours);

  /// The late-night surcharge (whole rupees) for the current schedule — non-zero
  /// only when the ride runs past 10pm. See [nightSurchargeFor].
  int get nightSurcharge =>
      nightSurchargeFor(scheduledAt: _scheduledAt, hours: _hours);

  /// The estimated total fare (whole rupees): [baseFare] plus [nightSurcharge].
  /// Updates as the customer changes the hours, start time, or car type.
  int get fare => baseFare + nightSurcharge;

  /// Sets the hire duration, clamped to [[minHours], [maxHours]]. A no-op when
  /// unchanged so we don't churn listeners.
  void setHours(int value) {
    final clamped = value.clamp(minHours, maxHours);
    if (clamped == _hours) return;
    _hours = clamped;
    notifyListeners();
  }

  void incrementHours() => setHours(_hours + 1);
  void decrementHours() => setHours(_hours - 1);

  /// Sets when the trip should start (date and time already combined).
  void setScheduledAt(DateTime when) {
    if (_scheduledAt == when) return;
    _scheduledAt = when;
    notifyListeners();
  }

  void selectCarType(CarType type) {
    if (_carType == type) return;
    _carType = type;
    notifyListeners();
  }

  void selectTransmission(Transmission value) {
    if (_transmission == value) return;
    _transmission = value;
    notifyListeners();
  }

  /// True once every required choice is made — gates the CTA. Hours, the start
  /// time, and transmission always have a value (the schedule is pre-filled);
  /// only the car type must still be chosen.
  bool get canConfirm => _carType != null;

  /// The assembled request, or null until [canConfirm].
  RoundTripBooking? get booking => canConfirm
      ? RoundTripBooking(
          pickup: pickup,
          hours: _hours,
          scheduledAt: _scheduledAt,
          carType: _carType!,
          transmission: _transmission,
          fare: fare,
        )
      : null;
}
