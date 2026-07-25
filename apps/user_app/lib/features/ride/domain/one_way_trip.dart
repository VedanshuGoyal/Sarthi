import 'car_type.dart';
import 'pickup_location.dart';
import 'transmission.dart';

/// The two ends of a One-Way trip, fixed once both location steps are done.
/// A record so provider families can key on it by value.
typedef OneWayRoute = ({PickupLocation start, PickupLocation destination});

/// Everything the customer chooses on the details step — the route plus the
/// start time and car — before the drive time is known. The review step takes
/// this, fetches the estimate for [scheduledAt], and only then can a full
/// [OneWayTrip] exist. A record so provider families can key on it by value.
typedef OneWayDraft = ({
  PickupLocation start,
  PickupLocation destination,
  DateTime scheduledAt,
  CarType carType,
  Transmission transmission,
});

/// A fully specified One-Way trip, ready to be sent for matchmaking.
///
/// The simplest journey: the driver collects the customer at [start] at
/// [scheduledAt] in the kind of car they asked for, and the ride ends at
/// [destination]. The customer never picks a duration — [estimatedTravelTime]
/// is the traffic-aware drive time the Routes API predicted for that start
/// time, and the booking is priced/planned from it.
class OneWayTrip {
  const OneWayTrip({
    required this.start,
    required this.destination,
    required this.scheduledAt,
    required this.estimatedTravelTime,
    required this.carType,
    required this.transmission,
  });

  final PickupLocation start;
  final PickupLocation destination;

  /// When the trip should start.
  final DateTime scheduledAt;

  /// The predicted drive time from [start] to [destination] when departing at
  /// [scheduledAt].
  final Duration estimatedTravelTime;

  final CarType carType;
  final Transmission transmission;

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'destination': destination.toJson(),
    'scheduledAt': scheduledAt.toIso8601String(),
    'estimatedTravelMinutes': estimatedTravelTime.inMinutes,
    'carType': carType.name,
    'transmission': transmission.name,
  };
}
