import 'driver.dart';

/// A logged-in driver session: the authenticated [driver] plus the opaque
/// bearer [token] the backend issued. The token is sent as
/// `Authorization: Bearer <token>` on authenticated requests.
class DriverAuthSession {
  const DriverAuthSession({required this.token, required this.driver});

  final String token;
  final Driver driver;

  factory DriverAuthSession.fromJson(Map<String, dynamic> json) {
    return DriverAuthSession(
      token: json['token'] as String,
      driver: Driver.fromJson(json['driver'] as Map<String, dynamic>),
    );
  }

  /// Serializes the session for secure storage; round-trips with [fromJson].
  Map<String, dynamic> toJson() => {'token': token, 'driver': driver.toJson()};
}

/// The outcome of verifying an OTP.
///
/// If the number already had a driver account, [registered] is true and
/// [session] carries the logged-in driver + token. If it's a new number,
/// [registered] is false and [session] is null — the caller then collects a
/// name and registers.
class DriverOtpResult {
  const DriverOtpResult({required this.registered, this.session});

  final bool registered;
  final DriverAuthSession? session;

  factory DriverOtpResult.fromJson(Map<String, dynamic> json) {
    final registered = json['registered'] as bool? ?? false;
    return DriverOtpResult(
      registered: registered,
      session: registered ? DriverAuthSession.fromJson(json) : null,
    );
  }
}
