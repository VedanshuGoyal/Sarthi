/// Where a ride sits in its life, as the backend reports it.
///
/// A ride the driver hasn't taken is [requested]; once accepted it moves
/// strictly forward — [accepted] → [arrived] → [inProgress] → [completed].
enum RideStatus {
  requested('requested', 'New request'),
  accepted('accepted', 'Upcoming'),
  arrived('arrived', 'At pickup'),
  inProgress('in_progress', 'On trip'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const RideStatus(this.wireName, this.label);

  /// The value the backend sends.
  final String wireName;

  /// Short label for status chips.
  final String label;

  static RideStatus fromWire(String? value) => RideStatus.values.firstWhere(
    (s) => s.wireName == value,
    orElse: () => RideStatus.requested,
  );

  /// The ride is the driver's and still ahead of them or underway.
  bool get isActive =>
      this == accepted || this == arrived || this == inProgress;
}

/// The three ways a customer books a driver.
enum TripKind {
  roundTrip('roundTrip', 'Round trip'),
  oneWay('oneWay', 'One way'),
  multiStop('multiStop', 'Multi-stop');

  const TripKind(this.wireName, this.label);

  final String wireName;
  final String label;

  static TripKind fromWire(String? value) => TripKind.values.firstWhere(
    (k) => k.wireName == value,
    orElse: () => TripKind.roundTrip,
  );
}

/// One address on a ride.
class RidePlace {
  const RidePlace({
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String address;
  final double lat;
  final double lng;

  /// The first comma-separated part — "Connaught Place" out of
  /// "Connaught Place, New Delhi, Delhi 110001, India" — for compact rows.
  String get shortName {
    final first = address.split(',').first.trim();
    return first.isEmpty ? address : first;
  }

  factory RidePlace.fromJson(Map<String, dynamic> json) => RidePlace(
    address: json['address'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0,
  );
}

/// An errand on a multi-stop ride.
class RideStop {
  const RideStop({required this.place, this.task = '', this.departBy});

  final RidePlace place;
  final String task;

  /// When the driver should leave this stop.
  final DateTime? departBy;

  factory RideStop.fromJson(Map<String, dynamic> json) => RideStop(
    place: RidePlace.fromJson(json['place'] as Map<String, dynamic>? ?? {}),
    task: json['task'] as String? ?? '',
    departBy: _time(json['departBy']),
  );
}

/// The customer's own car, which the driver drives.
class RideCar {
  const RideCar({
    required this.registration,
    required this.carType,
    required this.transmission,
  });

  final String registration;

  /// hatchback | sedan | suv | luxury.
  final String carType;

  /// manual | automatic.
  final String transmission;

  String get carTypeLabel => switch (carType) {
    'suv' => 'SUV',
    '' => 'Car',
    _ => '${carType[0].toUpperCase()}${carType.substring(1)}',
  };

  String get transmissionLabel => switch (transmission) {
    'manual' => 'Manual',
    'automatic' => 'Automatic',
    _ => '',
  };

  factory RideCar.fromJson(Map<String, dynamic> json) => RideCar(
    registration: json['registration'] as String? ?? '',
    carType: json['carType'] as String? ?? '',
    transmission: json['transmission'] as String? ?? '',
  );
}

/// Who the driver is driving for. Only sent once the ride is theirs.
class RideCustomer {
  const RideCustomer({required this.name, required this.phoneE164});

  final String name;
  final String phoneE164;

  factory RideCustomer.fromJson(Map<String, dynamic> json) => RideCustomer(
    name: json['name'] as String? ?? '',
    phoneE164: json['phoneE164'] as String? ?? '',
  );
}

/// A ride as the driver app shows it — an open request, or one of the
/// driver's own rides.
class Ride {
  const Ride({
    required this.id,
    required this.kind,
    required this.status,
    required this.scheduledAt,
    required this.endsAt,
    required this.farePaise,
    required this.pickup,
    this.fareEstimated = false,
    this.destination,
    this.stops = const [],
    this.hours,
    this.estimatedMinutes,
    this.car,
    this.customer,
    this.distanceM,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final TripKind kind;
  final RideStatus status;

  /// When the driver should be at the pickup.
  final DateTime scheduledAt;

  /// When the driver should be free again.
  final DateTime endsAt;

  /// The fare in paise. [fareEstimated] when the server derived it from the
  /// trip's length rather than the customer being quoted it.
  final int farePaise;
  final bool fareEstimated;

  final RidePlace pickup;

  /// Where a one-way trip ends.
  final RidePlace? destination;

  /// A multi-stop trip's errands, in order.
  final List<RideStop> stops;

  /// Hours hired, on a round trip.
  final int? hours;

  /// Predicted drive time, on a one-way trip.
  final int? estimatedMinutes;

  final RideCar? car;
  final RideCustomer? customer;

  /// Straight-line distance from the driver to the pickup, on requests.
  final double? distanceM;

  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// The fare in whole rupees, for display.
  int get fareRupees => (farePaise / 100).round();

  /// How long the driver is booked for.
  Duration get duration => endsAt.difference(scheduledAt);

  /// The last place on the route — the destination, the final stop, or (on a
  /// round trip) back at the pickup.
  RidePlace get finalPlace =>
      destination ?? (stops.isNotEmpty ? stops.last.place : pickup);

  /// A copy carrying a newer server state, keeping the customer if the
  /// update didn't include one.
  Ride mergedWith(Ride update) => update.customer == null && customer != null
      ? update._withCustomer(customer!)
      : update;

  Ride _withCustomer(RideCustomer c) => Ride(
    id: id,
    kind: kind,
    status: status,
    scheduledAt: scheduledAt,
    endsAt: endsAt,
    farePaise: farePaise,
    fareEstimated: fareEstimated,
    pickup: pickup,
    destination: destination,
    stops: stops,
    hours: hours,
    estimatedMinutes: estimatedMinutes,
    car: car,
    customer: c,
    distanceM: distanceM,
    acceptedAt: acceptedAt,
    arrivedAt: arrivedAt,
    startedAt: startedAt,
    completedAt: completedAt,
  );

  /// Parses the backend's ride, or returns null for one this app version
  /// can't read — a skipped row beats a crashed list.
  static Ride? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final scheduledAt = _time(json['scheduledAt']);
    final pickup = json['pickup'];
    if (id is! String ||
        scheduledAt == null ||
        pickup is! Map<String, dynamic>) {
      return null;
    }
    final dest = json['destination'];
    final car = json['car'];
    final customer = json['customer'];
    return Ride(
      id: id,
      kind: TripKind.fromWire(json['tripType'] as String?),
      status: RideStatus.fromWire(json['status'] as String?),
      scheduledAt: scheduledAt,
      endsAt:
          _time(json['endsAt']) ?? scheduledAt.add(const Duration(hours: 1)),
      farePaise: (json['farePaise'] as num?)?.toInt() ?? 0,
      fareEstimated: json['fareEstimated'] as bool? ?? false,
      pickup: RidePlace.fromJson(pickup),
      destination: dest is Map<String, dynamic>
          ? RidePlace.fromJson(dest)
          : null,
      stops: [
        for (final s in json['stops'] as List<dynamic>? ?? const [])
          if (s is Map<String, dynamic>) RideStop.fromJson(s),
      ],
      hours: (json['hours'] as num?)?.toInt(),
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
      car: car is Map<String, dynamic> ? RideCar.fromJson(car) : null,
      customer: customer is Map<String, dynamic>
          ? RideCustomer.fromJson(customer)
          : null,
      distanceM: (json['distanceM'] as num?)?.toDouble(),
      acceptedAt: _time(json['acceptedAt']),
      arrivedAt: _time(json['arrivedAt']),
      startedAt: _time(json['startedAt']),
      completedAt: _time(json['completedAt']),
    );
  }
}

/// What the driver can do to a ride. Each maps to
/// `POST /driver/rides/{id}/{wireName}`.
enum RideAction {
  accept('accept'),
  decline('decline'),
  arrive('arrive'),
  start('start'),
  complete('complete'),
  release('release');

  const RideAction(this.wireName);

  final String wireName;
}

/// Earnings over one window: the summed fares of rides completed in it.
class EarningsPeriod {
  const EarningsPeriod({this.farePaise = 0, this.rides = 0});

  final int farePaise;
  final int rides;

  int get rupees => (farePaise / 100).round();

  factory EarningsPeriod.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const EarningsPeriod();
    return EarningsPeriod(
      farePaise: (json['farePaise'] as num?)?.toInt() ?? 0,
      rides: (json['rides'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The earnings panel's summary, in IST calendar windows.
class Earnings {
  const Earnings({
    this.today = const EarningsPeriod(),
    this.week = const EarningsPeriod(),
    this.month = const EarningsPeriod(),
    this.total = const EarningsPeriod(),
  });

  final EarningsPeriod today;
  final EarningsPeriod week;
  final EarningsPeriod month;
  final EarningsPeriod total;

  factory Earnings.fromJson(Map<String, dynamic> json) => Earnings(
    today: EarningsPeriod.fromJson(json['today']),
    week: EarningsPeriod.fromJson(json['week']),
    month: EarningsPeriod.fromJson(json['month']),
    total: EarningsPeriod.fromJson(json['total']),
  );
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
