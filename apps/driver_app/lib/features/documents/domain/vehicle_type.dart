/// The gearbox(es) a driver is able to drive, collected on the Vehicle Type
/// document step so matchmaking can respect a customer's transmission
/// preference.
enum VehicleType {
  manual('Manual'),
  automatic('Automatic'),
  both('Manual and Automatic Both');

  const VehicleType(this.label);

  /// Human-readable label shown in the picker.
  final String label;
}
