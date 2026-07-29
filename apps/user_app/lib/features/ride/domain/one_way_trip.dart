import 'car.dart';
import 'pickup_location.dart';

/// The two ends of a One-Way trip, fixed once both location steps are done.
/// A record so provider families can key on it by value.
typedef OneWayRoute = ({PickupLocation start, PickupLocation destination});

/// Everything the customer chooses on the details step — the route plus the
/// start time and which saved car — before the drive time is known. The review
/// step takes this, fetches the estimate for [scheduledAt], and only then can
/// a full [OneWayTrip] exist. A record so provider families can key on it by
/// value ([Car] is value-equal for exactly this reason).
typedef OneWayDraft = ({
  PickupLocation start,
  PickupLocation destination,
  DateTime scheduledAt,
  Car car,
});

/// A fully specified One-Way trip, ready to be sent for matchmaking.
///
/// The simplest journey: the driver collects the customer at [start] at
/// [scheduledAt], drives the customer's own [car], and the ride ends at
/// [destination]. The customer never picks a duration — [estimatedTravelTime]
/// is the traffic-aware drive time the Routes API predicted for that start
/// time, and the booking is priced/planned from it.
class OneWayTrip {
  const OneWayTrip({
    required this.start,
    required this.destination,
    required this.scheduledAt,
    required this.estimatedTravelTime,
    required this.car,
  });

  final PickupLocation start;
  final PickupLocation destination;

  /// When the trip should start.
  final DateTime scheduledAt;

  /// The predicted drive time from [start] to [destination] when departing at
  /// [scheduledAt].
  final Duration estimatedTravelTime;

  /// The customer's saved car the driver is hired to drive.
  final Car car;

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'destination': destination.toJson(),
    'scheduledAt': scheduledAt.toIso8601String(),
    'estimatedTravelMinutes': estimatedTravelTime.inMinutes,
    'car': car.toJson(),
  };
}
