import 'trip_type.dart';

/// Where one of the customer's bookings stands, as the backend reports it.
enum BookingStatus {
  requested('requested', 'Finding a driver'),
  accepted('accepted', 'Driver assigned'),
  arrived('arrived', 'Driver at pickup'),
  inProgress('in_progress', 'On trip'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const BookingStatus(this.wireName, this.label);

  final String wireName;

  /// What the customer sees on the card.
  final String label;

  static BookingStatus fromWire(String? value) => BookingStatus.values
      .firstWhere((s) => s.wireName == value, orElse: () => requested);

  /// Not finished yet — worth showing on the home screen.
  bool get isActive => this != completed && this != cancelled;
}

/// One of the customer's bookings: what they booked, where it stands, the
/// driver once one accepts, and the code to give that driver to start.
///
/// A pure domain type; [MyBooking.tryParse] reads the backend's
/// `GET /me/bookings` shape.
class MyBooking {
  const MyBooking({
    required this.id,
    required this.tripType,
    required this.status,
    required this.scheduledAt,
    required this.pickupAddress,
    required this.farePaise,
    this.fareEstimated = false,
    this.destinationAddress,
    this.stopCount = 0,
    this.carRegistration,
    this.driverName,
    this.driverPhone,
    this.startOtp,
  });

  final String id;
  final TripType tripType;
  final BookingStatus status;
  final DateTime scheduledAt;
  final String pickupAddress;
  final String? destinationAddress;
  final int stopCount;
  final int farePaise;
  final bool fareEstimated;
  final String? carRegistration;

  /// The assigned driver, once one accepts.
  final String? driverName;
  final String? driverPhone;

  /// The code the driver needs to start the trip. Only sent while the driver
  /// is on the way or waiting at the pickup.
  final String? startOtp;

  int get fareRupees => (farePaise / 100).round();

  static TripType _tripType(Object? value) => switch (value) {
    'oneWay' => TripType.oneWay,
    'multiStop' => TripType.multiStop,
    _ => TripType.roundTrip,
  };

  /// Parses one booking, or null for one this app version can't read.
  static MyBooking? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final scheduledAt = json['scheduledAt'] is String
        ? DateTime.tryParse(json['scheduledAt'] as String)?.toLocal()
        : null;
    final pickup = json['pickup'];
    if (id is! String || scheduledAt == null || pickup is! Map) return null;
    final destination = json['destination'];
    final car = json['car'];
    final driver = json['driver'];
    final otp = json['startOtp'];
    return MyBooking(
      id: id,
      tripType: _tripType(json['tripType']),
      status: BookingStatus.fromWire(json['status'] as String?),
      scheduledAt: scheduledAt,
      pickupAddress: pickup['address'] as String? ?? '',
      destinationAddress: destination is Map
          ? destination['address'] as String?
          : null,
      stopCount: (json['stopCount'] as num?)?.toInt() ?? 0,
      farePaise: (json['farePaise'] as num?)?.toInt() ?? 0,
      fareEstimated: json['fareEstimated'] as bool? ?? false,
      carRegistration: car is Map ? car['registration'] as String? : null,
      driverName: driver is Map ? driver['name'] as String? : null,
      driverPhone: driver is Map ? driver['phoneE164'] as String? : null,
      startOtp: otp is String && otp.isNotEmpty ? otp : null,
    );
  }
}
