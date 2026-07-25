import 'car_type.dart';

/// The rate card that turns a Round Trip's hire [hours] into a base fare.
///
/// A pure domain type (no Flutter imports). Fares are whole rupees — this
/// tier's tariff, not floating money. Both tiers price the first two hours as
/// flat blocks, then add a flat [additionalHour] rate from the third hour on.
/// The base fare excludes the late-night surcharge — see [nightSurchargeFor].
class RoundTripTariff {
  const RoundTripTariff({
    required this.firstHour,
    required this.secondHour,
    required this.additionalHour,
  });

  /// Flat price for a 1-hour hire.
  final int firstHour;

  /// Flat price for a 2-hour hire (a block, not [firstHour] doubled).
  final int secondHour;

  /// Added for each hour beyond the second.
  final int additionalHour;

  /// The base fare, in rupees, for hiring for [hours]. Treats anything below 1
  /// as a single hour so callers needn't guard the lower bound.
  int fareFor(int hours) {
    if (hours <= 1) return firstHour;
    if (hours == 2) return secondHour;
    return secondHour + (hours - 2) * additionalHour;
  }

  /// Standard cars — hatchback, sedan, SUV all share this rate.
  static const standard = RoundTripTariff(
    firstHour: 139,
    secondHour: 240,
    additionalHour: 100,
  );

  /// Premium/executive cars carry a higher rate.
  static const luxury = RoundTripTariff(
    firstHour: 196,
    secondHour: 330,
    additionalHour: 110,
  );

  /// The tariff that applies to [carType]. Only luxury differs; every other
  /// class is priced at the [standard] rate.
  static RoundTripTariff forCarType(CarType carType) =>
      carType == CarType.luxury ? luxury : standard;
}

/// The hour of day (24h) at which the late-night surcharge kicks in.
const int nightSurchargeFromHour = 22; // 10pm

/// One-time fee added when any of the hire runs past 10pm.
const int nightFlatCharge = 50;

/// Added per hire-hour driven after 10pm (a partial hour counts as a full one).
const int nightHourlyCharge = 24;

/// How many hire-hours of a trip starting at [scheduledAt] for [hours] fall at
/// or after 10pm — the same tier for every car type.
///
/// Counts only the ride's own hours in the post-10pm window (a trip that starts
/// after 10pm is night for its whole length; one that ends before 10pm is not
/// night at all), rounding a partial final hour up. A ride whose evening 10pm
/// boundary never arrives before it ends (e.g. a small-hours ride) reads as no
/// night hours.
int nightHoursFor({required DateTime scheduledAt, required int hours}) {
  final finish = scheduledAt.add(Duration(hours: hours));
  final tenPm = DateTime(
    scheduledAt.year,
    scheduledAt.month,
    scheduledAt.day,
    nightSurchargeFromHour,
  );
  // Night is charged from the later of 10pm and the ride's own start.
  final nightStart = scheduledAt.isAfter(tenPm) ? scheduledAt : tenPm;
  if (!finish.isAfter(nightStart)) return 0;
  final minutes = finish.difference(nightStart).inMinutes;
  return (minutes / Duration.minutesPerHour).ceil();
}

/// The late-night surcharge (rupees) for a trip starting at [scheduledAt] for
/// [hours]: the flat [nightFlatCharge] plus [nightHourlyCharge] per night hour,
/// or 0 when none of the ride runs past 10pm.
int nightSurchargeFor({required DateTime scheduledAt, required int hours}) {
  final nightHours = nightHoursFor(scheduledAt: scheduledAt, hours: hours);
  if (nightHours == 0) return 0;
  return nightFlatCharge + nightHourlyCharge * nightHours;
}
