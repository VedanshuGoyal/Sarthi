/// The classes of vehicle a customer can request for a Round Trip.
///
/// A pure domain type (no Flutter imports): the presentation layer owns each
/// option's label, icon, and blurb. Ordered cheapest-to-premium so the chooser
/// can render them in that order.
enum CarType {
  /// Compact, budget-friendly city car.
  hatchback,

  /// Standard three-box car with a boot.
  sedan,

  /// Roomy sport-utility vehicle for luggage or larger groups.
  suv,

  /// Premium/executive-class vehicle.
  luxury,
}
