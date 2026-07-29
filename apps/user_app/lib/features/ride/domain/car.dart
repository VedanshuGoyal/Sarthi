import 'car_type.dart';
import 'transmission.dart';

/// A customer's saved car — the car a Sarthi driver is hired to drive.
///
/// Registered once (registration number, type, gearbox) and then picked from a
/// dropdown on every booking instead of re-describing the car each trip. The
/// backend is the source of truth; [registration] is the normalised plate it
/// stores (uppercase, separators stripped, e.g. "KA01AB1234").
///
/// Value-equal so provider families keyed on records containing a car (like
/// `OneWayDraft`) and dropdown selections compare by content, not identity.
class Car {
  const Car({
    required this.id,
    required this.registration,
    required this.type,
    required this.transmission,
  });

  /// The backend's id for this saved car.
  final String id;

  /// The normalised registration plate, e.g. "KA01AB1234".
  final String registration;

  final CarType type;
  final Transmission transmission;

  @override
  bool operator ==(Object other) =>
      other is Car &&
      other.id == id &&
      other.registration == registration &&
      other.type == type &&
      other.transmission == transmission;

  @override
  int get hashCode => Object.hash(id, registration, type, transmission);

  Map<String, dynamic> toJson() => {
    'id': id,
    'registration': registration,
    'carType': type.name,
    'transmission': transmission.name,
  };

  /// Parses one car, or null when malformed or naming an enum value this app
  /// version doesn't know — a skipped row beats a crashed list. Reads the
  /// backend's wire shape, which the on-device cache mirrors verbatim.
  static Car? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final registration = json['registration'] as String?;
    if (id == null || registration == null || registration.isEmpty) return null;
    final type = _byName(CarType.values, json['carType']);
    final transmission = _byName(Transmission.values, json['transmission']);
    if (type == null || transmission == null) return null;
    return Car(
      id: id,
      registration: registration,
      type: type,
      transmission: transmission,
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
