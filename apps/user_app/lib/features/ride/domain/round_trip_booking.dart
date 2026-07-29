import 'car.dart';
import 'pickup_location.dart';

/// A fully specified Round Trip request, ready to be sent for matchmaking.
///
/// The output of the booking-details step: it pins the confirmed [pickup] to
/// the customer's choices — how many [hours] to hire for, the [scheduledAt]
/// date/time to start, which of their saved cars ([car]) the driver will
/// drive, and the [fare] quoted for that selection.
class RoundTripBooking {
  const RoundTripBooking({
    required this.pickup,
    required this.hours,
    required this.scheduledAt,
    required this.car,
    required this.fare,
  });

  final PickupLocation pickup;

  /// How many hours the driver is hired for. At least 1.
  final int hours;

  /// When the trip should start.
  final DateTime scheduledAt;

  /// The customer's saved car the driver is hired to drive.
  final Car car;

  /// The quoted fare in whole rupees for [hours] at the car's tariff.
  final int fare;

  Map<String, dynamic> toJson() => {
    'pickup': pickup.toJson(),
    'hours': hours,
    'scheduledAt': scheduledAt.toIso8601String(),
    'car': car.toJson(),
    'fare': fare,
  };
}
