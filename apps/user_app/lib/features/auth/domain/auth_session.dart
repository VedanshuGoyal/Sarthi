import 'auth_user.dart';

/// A logged-in session: the authenticated [user] plus the opaque bearer [token]
/// the backend issued. The token is sent as `Authorization: Bearer <token>` on
/// authenticated requests.
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  /// Serializes the session for secure storage; round-trips with [fromJson].
  Map<String, dynamic> toJson() => {'token': token, 'user': user.toJson()};
}

/// The outcome of verifying an OTP.
///
/// If the number already had an account, [registered] is true and [session]
/// carries the logged-in user + token. If it's a new number, [registered] is
/// false and [session] is null — the caller then collects a profile and
/// registers, sending back [registrationTicket].
class OtpResult {
  const OtpResult({
    required this.registered,
    this.session,
    this.registrationTicket,
  });

  final bool registered;
  final AuthSession? session;

  /// For a new number: the one-time proof that this device verified it,
  /// which registering must send back. Null from a server that predates it.
  final String? registrationTicket;

  factory OtpResult.fromJson(Map<String, dynamic> json) {
    final registered = json['registered'] as bool? ?? false;
    return OtpResult(
      registered: registered,
      session: registered ? AuthSession.fromJson(json) : null,
      registrationTicket: json['registrationTicket'] as String?,
    );
  }
}
