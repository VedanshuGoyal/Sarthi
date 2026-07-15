/// A registered Sarthi customer.
///
/// This is the clean domain model the rest of the app consumes — produced by
/// [AuthRepository] from whatever the backend eventually returns. PostgreSQL is
/// the source of truth for accounts; this is just the in-app view of one.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.phoneE164,
    required this.name,
    required this.email,
    required this.dateOfBirth,
  });

  /// Server-assigned account id.
  final String id;

  /// Full E.164 phone number, e.g. `+919876543210`.
  final String phoneE164;

  final String name;
  final String email;
  final DateTime dateOfBirth;

  /// Builds a user from the backend's JSON (`/auth/register` response).
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      phoneE164: json['phoneE164'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
    );
  }

  /// Serializes the user, e.g. to cache a session in secure storage. The shape
  /// mirrors [AuthUser.fromJson] so it round-trips.
  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneE164': phoneE164,
    'name': name,
    'email': email,
    'dateOfBirth': dateOfBirth.toIso8601String(),
  };

  @override
  String toString() => 'AuthUser(id: $id, name: $name, phone: $phoneE164)';
}
