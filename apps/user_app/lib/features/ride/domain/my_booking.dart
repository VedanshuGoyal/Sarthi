import 'car_type.dart';
import 'geo_point.dart';
import 'scheduling.dart';
import 'transmission.dart';
import 'trip_type.dart';

/// Where one of the customer's bookings stands, as the backend reports it.
enum BookingStatus {
  requested('requested', 'Finding a driver'),
  accepted('accepted', 'Driver assigned'),
  arrived('arrived', 'Driver at pickup'),
  inProgress('in_progress', 'On trip'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled'),

  /// No driver took it before it closed, 30 minutes before the start.
  expired('expired', 'No driver found');

  const BookingStatus(this.wireName, this.label);

  final String wireName;

  /// What the customer sees on the card.
  final String label;

  static BookingStatus fromWire(String? value) => BookingStatus.values
      .firstWhere((s) => s.wireName == value, orElse: () => requested);

  /// Not finished yet — an upcoming ride.
  bool get isActive =>
      this != completed && this != cancelled && this != expired;
}

/// Where the money for a completed ride stands.
enum RidePaymentStatus {
  /// Not completed yet — nothing to pay.
  none(''),

  /// Completed; the customer hasn't paid.
  due('due'),

  /// The customer has paid.
  paid('paid');

  const RidePaymentStatus(this.wireName);

  final String wireName;

  static RidePaymentStatus fromWire(Object? value) => values.firstWhere(
    (s) => s != none && s.wireName == value,
    orElse: () => none,
  );
}

/// Why a customer can say they're cancelling, in the order the cancel sheet
/// lists them. Mirrors the server's list; "Other" takes free text.
const List<String> cancelReasons = [
  'Plans changed',
  'Booked by mistake',
  'Driver asked me to cancel',
  'Driver is not responding',
  'Found another option',
  otherCancelReason,
];

/// The reason that lets the customer type their own.
const String otherCancelReason = 'Other';

/// The longest cancel reason the server accepts.
const int maxCancelReasonLength = 200;

/// The longest rating note the server accepts.
const int maxRatingNoteLength = 500;

/// One planned stop on a booked Multi-Stop trip: where, what the driver does
/// there, and when they should move on.
class BookingStop {
  const BookingStop({
    required this.address,
    required this.task,
    this.point,
    this.departBy,
  });

  final String address;
  final GeoPoint? point;

  /// The errand, in the customer's words.
  final String task;
  final DateTime? departBy;
}

/// The stars (1–5) and optional note one side of a ride gave the other.
class RideRating {
  const RideRating({required this.stars, this.note});

  final int stars;
  final String? note;
}

/// One of the customer's bookings: what they booked, where it stands, the
/// driver once one accepts, the code to give that driver to start, and how
/// the trip went.
///
/// A pure domain type; [MyBooking.tryParse] reads the backend's
/// `GET /me/bookings` shape. Everything past the core trip is optional, so
/// older servers' payloads still parse.
class MyBooking {
  const MyBooking({
    required this.id,
    required this.tripType,
    required this.status,
    required this.scheduledAt,
    required this.pickupAddress,
    required this.farePaise,
    this.fareEstimated = false,
    this.pickupPoint,
    this.destinationAddress,
    this.destinationPoint,
    this.stopCount = 0,
    this.stops = const [],
    this.hours,
    this.estimatedMinutes,
    this.endsAt,
    this.carRegistration,
    this.carType,
    this.transmission,
    this.driverName,
    this.driverPhone,
    this.driverRating,
    this.driverRatingCount = 0,
    this.driverPhotoVersion,
    this.startOtp,
    this.createdAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.myRating,
    this.paymentStatus = RidePaymentStatus.none,
    this.paidAt,
  });

  final String id;
  final TripType tripType;
  final BookingStatus status;
  final DateTime scheduledAt;
  final String pickupAddress;
  final GeoPoint? pickupPoint;
  final String? destinationAddress;
  final GeoPoint? destinationPoint;

  /// How many stops a Multi-Stop trip has — [stops].length on servers that
  /// send the stops themselves.
  final int stopCount;
  final List<BookingStop> stops;

  /// How many hours a Round Trip is booked for.
  final int? hours;

  /// The expected drive time of a One-Way or Multi-Stop trip.
  final int? estimatedMinutes;
  final DateTime? endsAt;
  final int farePaise;
  final bool fareEstimated;
  final String? carRegistration;
  final CarType? carType;
  final Transmission? transmission;

  /// The assigned driver, once one accepts.
  final String? driverName;
  final String? driverPhone;

  /// The driver's average stars; null until someone has rated them.
  final double? driverRating;
  final int driverRatingCount;

  /// Changes whenever the driver retakes their photo; null when they have
  /// none. Part of the photo's URL, so a cached copy is never a stale one.
  final String? driverPhotoVersion;

  /// The code the driver needs to start the trip. Only sent while the driver
  /// is on the way or waiting at the pickup.
  final String? startOtp;

  /// When each step of the trip happened, as far as it got.
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// Who cancelled — `customer` when it was this customer.
  final String? cancelledBy;
  final String? cancelReason;

  /// What this customer gave the driver, once they've rated the trip.
  final RideRating? myRating;

  /// Whether the completed ride is paid for, and when it was.
  final RidePaymentStatus paymentStatus;
  final DateTime? paidAt;

  int get fareRupees => (farePaise / 100).round();

  /// The driver's first name, for friendlier lines ("Ravi is 2 km away").
  String? get driverFirstName {
    final name = driverName?.trim();
    if (name == null || name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }

  /// Whether the customer may still cancel: any time before the trip starts.
  /// A request that expired has nothing left to cancel.
  bool get canCancel =>
      status == BookingStatus.requested ||
      status == BookingStatus.accepted ||
      status == BookingStatus.arrived;

  /// Whether the trip is finished and waiting for the customer to pay.
  bool get canPay =>
      status == BookingStatus.completed &&
      paymentStatus == RidePaymentStatus.due &&
      farePaise >= 100;

  /// Whether the trip is finished and waiting for the customer's stars.
  bool get canRate => status == BookingStatus.completed && myRating == null;

  /// Whether the driver's live location is visible at [now]: once they're at
  /// the pickup or on the trip, or from [driverTrackingLead] before the start
  /// once assigned. Mirrors the server's rule.
  bool isInTrackingWindow(DateTime now) => switch (status) {
    BookingStatus.arrived || BookingStatus.inProgress => true,
    BookingStatus.accepted => !now.isBefore(
      scheduledAt.subtract(driverTrackingLead),
    ),
    _ => false,
  };

  /// How long the trip is booked for: the hours of a Round Trip, the expected
  /// drive of the others, else the booked window.
  Duration? get duration {
    if (hours case final hours?) return Duration(hours: hours);
    if (estimatedMinutes case final minutes?) return Duration(minutes: minutes);
    return endsAt?.difference(scheduledAt);
  }

  /// "Cancelled by you" and the like, or null when the server didn't say.
  String? get cancelledByLabel => switch (cancelledBy) {
    null || '' => null,
    'customer' => 'Cancelled by you',
    'driver' => 'Cancelled by your driver',
    _ => 'Cancelled',
  };

  /// Who cancelled and why, on one line — "Cancelled by you · Plans changed".
  String? get cancellationSummary {
    final parts = [?cancelledByLabel, ?_nonEmpty(cancelReason)];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static TripType _tripType(Object? value) => switch (value) {
    'oneWay' => TripType.oneWay,
    'multiStop' => TripType.multiStop,
    _ => TripType.roundTrip,
  };

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// A place's coordinates, or null when missing — or the `0,0` placeholder
  /// the server sends for a place it has no fix for.
  static GeoPoint? _point(Object? place) {
    if (place is! Map) return null;
    final lat = place['lat'];
    final lng = place['lng'];
    if (lat is! num || lng is! num || (lat == 0 && lng == 0)) return null;
    return GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble());
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static BookingStop? _stop(Object? json) {
    if (json is! Map) return null;
    final place = json['place'];
    return BookingStop(
      address: place is Map ? place['address'] as String? ?? '' : '',
      point: _point(place),
      task: json['task'] as String? ?? '',
      departBy: _time(json['departBy']),
    );
  }

  static RideRating? _rating(Object? json) {
    if (json is! Map) return null;
    final stars = json['stars'];
    if (stars is! num || stars < 1 || stars > 5) return null;
    return RideRating(
      stars: stars.toInt(),
      note: _nonEmpty(json['note'] as String?),
    );
  }

  /// Parses one booking, or null for one this app version can't read.
  ///
  /// A request still open past [driverAcceptCutoff] before its start reads
  /// as [BookingStatus.expired] even if the server hasn't said so — older
  /// servers don't. [now] is a seam for tests.
  static MyBooking? tryParse(Object? json, {DateTime? now}) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final scheduledAt = _time(json['scheduledAt']);
    final pickup = json['pickup'];
    if (id is! String || scheduledAt == null || pickup is! Map) return null;
    final destination = json['destination'];
    final car = json['car'];
    final driver = json['driver'];
    final otp = json['startOtp'];
    final stops = [
      for (final stop in json['stops'] as List<dynamic>? ?? const [])
        ?_stop(stop),
    ];
    final ratingCount = driver is Map
        ? (driver['ratingCount'] as num?)?.toInt() ?? 0
        : 0;
    var status = BookingStatus.fromWire(json['status'] as String?);
    if (status == BookingStatus.requested &&
        (now ?? DateTime.now()).isAfter(
          scheduledAt.subtract(driverAcceptCutoff),
        )) {
      status = BookingStatus.expired;
    }
    return MyBooking(
      id: id,
      tripType: _tripType(json['tripType']),
      status: status,
      scheduledAt: scheduledAt,
      pickupAddress: pickup['address'] as String? ?? '',
      pickupPoint: _point(pickup),
      destinationAddress: destination is Map
          ? destination['address'] as String?
          : null,
      destinationPoint: _point(destination),
      stopCount: (json['stopCount'] as num?)?.toInt() ?? stops.length,
      stops: stops,
      hours: (json['hours'] as num?)?.toInt(),
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
      endsAt: _time(json['endsAt']),
      farePaise: (json['farePaise'] as num?)?.toInt() ?? 0,
      fareEstimated: json['fareEstimated'] as bool? ?? false,
      carRegistration: car is Map ? car['registration'] as String? : null,
      carType: car is Map ? _byName(CarType.values, car['carType']) : null,
      transmission: car is Map
          ? _byName(Transmission.values, car['transmission'])
          : null,
      driverName: driver is Map ? driver['name'] as String? : null,
      driverPhone: driver is Map ? driver['phoneE164'] as String? : null,
      // The server omits the average until someone rates the driver.
      driverRating: driver is Map && ratingCount > 0
          ? (driver['rating'] as num?)?.toDouble()
          : null,
      driverRatingCount: ratingCount,
      driverPhotoVersion: driver is Map
          ? _nonEmpty(driver['photoVersion'] as String?)
          : null,
      startOtp: otp is String && otp.isNotEmpty ? otp : null,
      createdAt: _time(json['createdAt']),
      acceptedAt: _time(json['acceptedAt']),
      arrivedAt: _time(json['arrivedAt']),
      startedAt: _time(json['startedAt']),
      completedAt: _time(json['completedAt']),
      cancelledAt: _time(json['cancelledAt']),
      cancelledBy: json['cancelledBy'] as String?,
      cancelReason: _nonEmpty(json['cancelReason'] as String?),
      myRating: _rating(json['myRating']),
      paymentStatus: RidePaymentStatus.fromWire(json['paymentStatus']),
      paidAt: _time(json['paidAt']),
    );
  }
}
