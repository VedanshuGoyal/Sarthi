/// The gearbox a customer wants the assigned car (and driver) to have.
///
/// A pure domain type; presentation owns the labels. Kept separate from
/// [CarType] because a customer picks a class of car *and* how it shifts.
enum Transmission {
  /// Self-shifting gearbox.
  automatic,

  /// Clutch-and-stick manual gearbox.
  manual,
}
