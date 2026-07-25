import 'car_type.dart';
import 'pickup_location.dart';
import 'transmission.dart';

/// A fully specified Round Trip request, ready to be sent for matchmaking.
///
/// The output of the booking-details step: it pins the confirmed [pickup] to
/// the customer's choices — how many [hours] to hire for, the [scheduledAt]
/// date/time to start, the [carType]/[transmission] of car they want, and the
/// [fare] quoted for that selection.
class RoundTripBooking {
  const RoundTripBooking({
    required this.pickup,
    required this.hours,
    required this.scheduledAt,
    required this.carType,
    required this.transmission,
    required this.fare,
  });

  final PickupLocation pickup;

  /// How many hours the driver is hired for. At least 1.
  final int hours;

  /// When the trip should start.
  final DateTime scheduledAt;

  final CarType carType;
  final Transmission transmission;

  /// The quoted fare in whole rupees for [hours] at [carType]'s tariff.
  final int fare;

  Map<String, dynamic> toJson() => {
    'pickup': pickup.toJson(),
    'hours': hours,
    'scheduledAt': scheduledAt.toIso8601String(),
    'carType': carType.name,
    'transmission': transmission.name,
    'fare': fare,
  };
}
