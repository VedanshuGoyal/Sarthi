/// The kinds of journey a customer can book from the post-login landing.
///
/// A pure domain type (no Flutter imports): the presentation layer owns how
/// each option is labelled and iconed. Kept deliberately small — new trip
/// modes are added here as the product grows.
enum TripType {
  /// Hire one or more drivers by the hour for an out-and-back journey; the
  /// customer also chooses how many hourly drivers they need.
  roundTrip,

  /// A single booking that visits several stops in sequence.
  multiStop,
}
