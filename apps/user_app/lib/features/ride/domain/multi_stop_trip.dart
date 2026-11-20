import 'car.dart';
import 'pickup_location.dart';
import 'trip_stop.dart';

/// A fully specified Multi-Stop trip, ready to be sent for matchmaking.
///
/// The output of the planner step: the driver collects the customer's [car]
/// at [start] at [scheduledAt], then works through [stops] in order — each
/// one a [TripStop] naming the place, the errand to run there, and the time
/// to leave by. The car's gearbox decides which drivers are offered the
/// trip, as on the other trip types.
class MultiStopTrip {
  const MultiStopTrip({
    required this.start,
    required this.scheduledAt,
    required this.stops,
    required this.car,
  });

  /// Where the trip begins (usually where the customer or car is).
  final PickupLocation start;

  /// When the trip should start.
  final DateTime scheduledAt;

  /// The stops in visiting order. Never empty; each stop's [TripStop.departBy]
  /// is later than the previous one's, and the first is after [scheduledAt].
  final List<TripStop> stops;

  /// The customer's saved car the driver is hired to drive.
  final Car car;

  /// When the plan wraps up: the departure deadline of the final stop.
  DateTime get endsAt => stops.last.departBy;

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    'stops': [for (final stop in stops) stop.toJson()],
    'car': car.toJson(),
  };
}
