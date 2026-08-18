/// A registered Sarthi driver.
///
/// This is the clean domain model the rest of the app consumes — produced by
/// [DriverAuthRepository] from whatever the backend returns. PostgreSQL is the
/// source of truth for accounts; this is just the in-app view of one.
class Driver {
  const Driver({required this.id, required this.phoneE164, required this.name});

  /// Server-assigned account id.
  final String id;

  /// Full E.164 phone number, e.g. `+919876543210`.
  final String phoneE164;

  final String name;

  /// Builds a driver from the backend's JSON (`/driver/auth/register` response).
  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'] as String,
      phoneE164: json['phoneE164'] as String,
      name: json['name'] as String,
    );
  }

  /// Serializes the driver, e.g. to cache a session in secure storage. The
  /// shape mirrors [Driver.fromJson] so it round-trips.
  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneE164': phoneE164,
    'name': name,
  };

  @override
  String toString() => 'Driver(id: $id, name: $name, phone: $phoneE164)';
}
