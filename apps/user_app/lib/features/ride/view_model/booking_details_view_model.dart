import 'package:flutter/foundation.dart';

import '../domain/car.dart';
import '../domain/pickup_location.dart';
import '../domain/round_trip_booking.dart';
import '../domain/round_trip_fare.dart';
import '../domain/scheduling.dart' as scheduling;

/// Drives Round Trip's "booking details" step (hours, schedule, which car).
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient form state
/// and exposes command methods the view calls. The pickup is not part of it —
/// the screen's pickup row owns that (see `TripStartViewModel`) and hands it
/// to [bookingFrom]. It holds
/// no business logic and never touches widgets, the network, or storage — the
/// saved-car *list* lives in the saved-cars view model; this one only holds
/// which car was picked.
class BookingDetailsViewModel extends ChangeNotifier {
  /// The `initial*` seams let previews and tests start in a given state
  /// without tapping through the UI; production starts with the defaults.
  /// [clock] is the "now" the too-soon checks use (a seam for tests).
  BookingDetailsViewModel({
    int initialHours = 2,
    DateTime? initialScheduledAt,
    Car? initialCar,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _hours = initialHours.clamp(minHours, maxHours),
       _scheduledAt = initialScheduledAt ?? defaultScheduledAt(clock?.call()),
       _car = initialCar;

  final DateTime Function() _clock;

  /// Whether the chosen start is too soon for a driver to accept in time.
  bool get isTooSoon => scheduling.isTooSoonToBook(_scheduledAt, _clock());

  /// Whether the time picker may offer [start] (see `earliestStart`).
  bool isStartAvailable(DateTime start) =>
      !start.isBefore(scheduling.earliestStart(_clock()));

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

  Car? _car;

  /// The saved car picked for this trip; null until the customer picks one.
  Car? get car => _car;

  bool get canDecrementHours => _hours > minHours;
  bool get canIncrementHours => _hours < maxHours;

  /// The tariff for the current selection. Until a car is picked we preview
  /// the standard rate; choosing a luxury car re-prices at the premium rate.
  RoundTripTariff get _tariff => _car == null
      ? RoundTripTariff.standard
      : RoundTripTariff.forCarType(_car!.type);

  /// The base fare (whole rupees) for the current [hours] under the applicable
  /// tariff, before any late-night surcharge.
  int get baseFare => _tariff.fareFor(_hours);

  /// The late-night surcharge (whole rupees) for the current schedule — non-zero
  /// only when the ride runs past 10pm. See [nightSurchargeFor].
  int get nightSurcharge =>
      nightSurchargeFor(scheduledAt: _scheduledAt, hours: _hours);

  /// The estimated total fare (whole rupees): [baseFare] plus [nightSurcharge].
  /// Updates as the customer changes the hours, start time, or car.
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

  void selectCar(Car car) {
    if (_car == car) return;
    _car = car;
    notifyListeners();
  }

  /// True once every choice on this form is made — with a pickup, gates the
  /// CTA. Hours and the start time always have a value (the schedule is
  /// pre-filled); the car must still be chosen, and the start must not be
  /// too soon.
  bool get canConfirm => _car != null && !isTooSoon;

  /// The assembled request from [pickup], or null until [canConfirm].
  RoundTripBooking? bookingFrom(PickupLocation pickup) => canConfirm
      ? RoundTripBooking(
          pickup: pickup,
          hours: _hours,
          scheduledAt: _scheduledAt,
          car: _car!,
          fare: fare,
        )
      : null;
}
