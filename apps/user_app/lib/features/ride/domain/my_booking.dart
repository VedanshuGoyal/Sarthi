import 'dart:math' show max;

import 'car_type.dart';
import 'geo_point.dart';
import 'scheduling.dart';
import 'transmission.dart';
import 'trip_type.dart';

/// Where one of the customer's bookings stands, as the backend reports it.
/// What the customer sees for each is `labelIn` in `ride_labels.dart`.
enum BookingStatus {
  requested('requested'),
  accepted('accepted'),
  arrived('arrived'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled'),

  /// No driver took it before it closed, 30 minutes before the start.
  expired('expired');

  const BookingStatus(this.wireName);

  final String wireName;

  static BookingStatus fromWire(String? value) => BookingStatus.values
      .firstWhere((s) => s.wireName == value, orElse: () => requested);

  /// Not finished yet — an upcoming ride.
  bool get isActive =>
      this != completed && this != cancelled && this != expired;
}

/// Where the money for a completed ride — or for a cancellation fee — stands.
enum RidePaymentStatus {
  /// Not completed yet, or cancelled for free — nothing to pay.
  none(''),

  /// Completed, or cancelled with a fee; the customer hasn't paid.
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

/// What cancelling costs once the driver is at the pickup, under the
/// cancellation policy (owner's decision, 17 Nov 2026). Only used to tell the
/// customer before the driver gets there; what a cancel actually costs is
/// the server's `cancellationFeePaise` on the booking.
const int pickupCancellationFeePaise = 5000;

/// How long a trip can run past its booked hours before the extra time is
/// charged, by the hour. Mirrors the server's over-time rule (owner's
/// decision, 17 Nov 2026).
const Duration overtimeGrace = Duration(minutes: 15);

/// What the customer owes on bookings other than the one at hand — unpaid
/// finished rides and cancellation fees — collected together with that
/// one's payment: [paise], and whether it's all one ride's ([oneRide]),
/// said only when the rides list shows it.
typedef EarlierDues = ({int paise, bool oneRide});

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

/// What one line of a payment paid for.
enum PaymentLineKind {
  /// A finished ride's fare.
  ride('ride'),

  /// The fee of a ride cancelled once the driver was at the pickup.
  cancellationFee('cancellation_fee');

  const PaymentLineKind(this.wireName);

  final String wireName;

  /// Anything this app version doesn't know reads as a ride.
  static PaymentLineKind fromWire(Object? value) =>
      value == cancellationFee.wireName ? cancellationFee : ride;
}

/// One booking a payment paid, as its receipt lists it: which booking, what
/// for, the server's short [label] for it ("Round trip · Tue 17 Nov") and
/// its part of the payment.
class PaymentLine {
  const PaymentLine({
    required this.bookingId,
    required this.kind,
    this.label,
    required this.amountPaise,
  });

  final String bookingId;
  final PaymentLineKind kind;

  /// The server's label, as sent; null when it sent none (the receipt then
  /// names the line by its [kind]).
  final String? label;
  final int amountPaise;

  /// Reads one entry of a payment's `lines`, or null when it names no
  /// booking or no positive amount.
  static PaymentLine? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['bookingId'];
    final amount = json['amountPaise'];
    if (id is! String || id.isEmpty || amount is! num || amount <= 0) {
      return null;
    }
    final kind = PaymentLineKind.fromWire(json['kind']);
    final label = json['label'];
    return PaymentLine(
      bookingId: id,
      kind: kind,
      label: label is String && label.trim().isNotEmpty ? label.trim() : null,
      amountPaise: amount.toInt(),
    );
  }
}

/// How a paid ride was paid, for its receipt: the gateway's payment mode
/// (`UPI_INTENT`, `UPI_QR`, …) or `CASH` / `WAIVED` for a ride MOJUD settled
/// by hand, with the references a dispute would need.
///
/// One payment can pay several of the customer's bookings at once (what
/// they owed on earlier rides is collected with their next payment):
/// [totalPaise] is then what the whole payment came to and [lines] every
/// booking it paid, this one included.
class RidePayment {
  const RidePayment({
    required this.mode,
    this.utr,
    this.transactionId,
    this.merchantOrderId,
    this.paidAt,
    this.totalPaise,
    this.lines = const [],
  });

  /// As the server sent it; may be empty.
  final String mode;
  final String? utr;
  final String? transactionId;
  final String? merchantOrderId;
  final DateTime? paidAt;

  /// What the whole payment came to; null from servers that don't say, and
  /// for a ride settled by hand.
  final int? totalPaise;

  /// Every booking the payment paid; empty when the server didn't say.
  final List<PaymentLine> lines;

  /// What the payment paid besides booking [bookingId]: empty when it paid
  /// that booking alone (or the server didn't list it).
  List<PaymentLine> besides(String bookingId) => [
    for (final line in lines)
      if (line.bookingId != bookingId) line,
  ];

  /// What the whole payment came to: [totalPaise], else its [lines] added
  /// up.
  int get paidPaise =>
      totalPaise ?? lines.fold(0, (sum, line) => sum + line.amountPaise);

  /// The bank's UTR, else the gateway's transaction id; null when neither.
  String? get reference => utr ?? transactionId;

  /// Reads a booking's `payment` block, or null when it's missing or not an
  /// object.
  static RidePayment? tryParse(Object? json) {
    if (json is! Map) return null;
    final mode = json['mode'];
    final paidAt = json['paidAt'];
    final total = json['totalPaise'];
    final lines = json['lines'];
    return RidePayment(
      mode: mode is String ? mode : '',
      utr: _text(json['utr']),
      transactionId: _text(json['transactionId']),
      merchantOrderId: _text(json['merchantOrderId']),
      paidAt: paidAt is String ? DateTime.tryParse(paidAt)?.toLocal() : null,
      totalPaise: total is num && total > 0 ? total.toInt() : null,
      lines: [
        if (lines is List)
          for (final line in lines) ?PaymentLine.tryParse(line),
      ],
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// What a Round Trip's fare is made of: the hourly tariff and the late-night
/// surcharge, in paise. The server only sends it when the two add up to the
/// fare.
class FareBreakdown {
  const FareBreakdown({required this.basePaise, this.nightPaise = 0});

  final int basePaise;
  final int nightPaise;

  int get baseRupees => (basePaise / 100).round();
  int get nightRupees => (nightPaise / 100).round();

  /// Reads a booking's `fareBreakdown` block, or null when it's missing or
  /// malformed.
  static FareBreakdown? tryParse(Object? json) {
    if (json is! Map) return null;
    final base = json['basePaise'];
    final night = json['nightPaise'];
    if (base is! num || base <= 0) return null;
    if (night != null && (night is! num || night < 0)) return null;
    return FareBreakdown(
      basePaise: base.toInt(),
      nightPaise: (night as num?)?.toInt() ?? 0,
    );
  }
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
    this.payment,
    this.fareBreakdown,
    this.cancellationFeePaise = 0,
    this.bookedFarePaise,
    this.carriedPaise = 0,
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

  /// How a paid ride was paid, for its receipt; null until it's paid, and
  /// from servers that don't say.
  final RidePayment? payment;

  /// A Round Trip's base fare and night surcharge; null when not sent.
  final FareBreakdown? fareBreakdown;

  /// While the driver waits at the pickup: what cancelling now costs. On a
  /// cancelled ride: the fee charged, paid like a fare (see
  /// [paymentStatus]). 0 when there's none.
  final int cancellationFeePaise;

  /// The fare as booked, on a trip charged for the time actually used —
  /// ended early by the customer, or run past its booked time. [farePaise]
  /// is then that charge. Null on every other booking.
  final int? bookedFarePaise;

  /// What the customer owes on their other bookings (unpaid finished rides,
  /// unpaid cancellation fees), collected together with this booking's
  /// payment. Sent on unpaid bookings that are active or due; 0 otherwise.
  final int carriedPaise;

  int get fareRupees => (farePaise / 100).round();

  /// Whether this ride was cancelled with a fee to pay, or paid.
  bool get hasCancellationFee =>
      status == BookingStatus.cancelled && cancellationFeePaise > 0;

  /// What cancelling right now costs: the fee once the driver is at the
  /// pickup, 0 before then (and from servers without the fee).
  int get cancelFeeNowPaise => canCancel ? cancellationFeePaise : 0;

  /// Whether the finished trip was charged for the time actually used
  /// instead of as booked: the customer ended it early, or it ran past its
  /// booked time. [bookedFarePaise] is then the fare as booked.
  bool get chargedByTime =>
      status == BookingStatus.completed && bookedFarePaise != null;

  /// Whether the customer ended the trip before its booked end: charged for
  /// the time used, at most the booked fare.
  bool get endedEarly => chargedByTime && farePaise <= bookedFarePaise!;

  /// Whether the trip ran past its booked time (and the grace), so the
  /// extra hours were charged: more than the booked fare.
  bool get ranOver => chargedByTime && farePaise > bookedFarePaise!;

  /// What the customer pays for this booking: the cancellation fee of a
  /// cancelled ride, the fare of any other.
  int get chargePaise =>
      status == BookingStatus.cancelled ? cancellationFeePaise : farePaise;

  /// What paying for this booking collects: its own [chargePaise] plus what
  /// is owed on the customer's other bookings ([carriedPaise]).
  int get totalDuePaise => chargePaise + carriedPaise;

  /// The customer's other bookings this booking's payment also paid — what
  /// they owed on them, collected at the same time. Empty when it paid this
  /// booking alone, or isn't paid yet.
  List<PaymentLine> get paidTogetherWith => payment?.besides(id) ?? const [];

  /// The hours the trip is booked for: a Round Trip's [hours]; for the
  /// others, the booked window ([endsAt] − [scheduledAt]) rounded up to
  /// whole hours, at least 1. Null when neither is known. Mirrors the
  /// server's over-time rule.
  int? get bookedHours {
    if (tripType == TripType.roundTrip && (hours ?? 0) > 0) return hours;
    final end = endsAt;
    if (end == null) return null;
    return max(_startedHours(end.difference(scheduledAt)), 1);
  }

  /// From when a trip in progress is past its booked time and the extra
  /// time is charged: [startedAt] plus [bookedHours] plus [overtimeGrace].
  /// Null when either is unknown.
  DateTime? get overtimeFrom {
    final started = startedAt;
    final booked = bookedHours;
    if (started == null || booked == null) return null;
    return started.add(Duration(hours: booked) + overtimeGrace);
  }

  /// Whether the trip is in progress and, at [now], past its booked time —
  /// extra time is being charged by the hour.
  bool isPastBookedTime(DateTime now) {
    final from = overtimeFrom;
    return status == BookingStatus.inProgress &&
        from != null &&
        now.isAfter(from);
  }

  /// The hours a finished trip took, each started hour counted as a whole
  /// one, at least 1: what a trip that [ranOver] was charged for. Null when
  /// the start or end time is missing.
  int? get hoursUsed {
    final started = startedAt;
    final ended = completedAt;
    if (started == null || ended == null || ended.isBefore(started)) {
      return null;
    }
    // Whole minutes first, as the server prices it: 2 h 0 min 30 s is 2 h.
    return max((ended.difference(started).inMinutes + 59) ~/ 60, 1);
  }

  /// Each started hour of [d] counted as a whole one.
  static int _startedHours(Duration d) =>
      (d.inMicroseconds / Duration.microsecondsPerHour).ceil();

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

  /// Whether the customer has something to pay for this booking: a
  /// finished trip's fare, or the fee of a ride cancelled at the pickup.
  bool get canPay =>
      (status == BookingStatus.completed || hasCancellationFee) &&
      paymentStatus == RidePaymentStatus.due &&
      chargePaise >= 100;

  /// Whether the customer may end the trip now, paying for the time used.
  bool get canEndTrip => status == BookingStatus.inProgress;

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

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static TripType _tripType(Object? value) => switch (value) {
    'oneWay' => TripType.oneWay,
    'multiStop' => TripType.multiStop,
    _ => TripType.roundTrip,
  };

  /// A positive amount in paise, or null for a missing or non-positive one.
  static int? _paise(Object? value) =>
      value is num && value > 0 ? value.toInt() : null;

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
      // Blank once the ride has been over a while: the number is gone.
      driverPhone: driver is Map
          ? _nonEmpty(driver['phoneE164'] as String?)
          : null,
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
      payment: RidePayment.tryParse(json['payment']),
      fareBreakdown: FareBreakdown.tryParse(json['fareBreakdown']),
      cancellationFeePaise: _paise(json['cancellationFeePaise']) ?? 0,
      bookedFarePaise: _paise(json['bookedFarePaise']),
      carriedPaise: _paise(json['carriedPaise']) ?? 0,
    );
  }
}
