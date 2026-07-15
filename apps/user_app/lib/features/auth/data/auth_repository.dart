import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/auth_session.dart';

/// Raised when the backend rejects a request (bad OTP, duplicate account, …).
/// [message] is safe to show to the user.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}

/// Raised for a wrong verification code (`otp_incorrect`). Distinct type so the
/// view model can count failed attempts toward the invalidation cap.
class OtpIncorrectException extends AuthException {
  const OtpIncorrectException(super.message);
}

/// Raised when the backend has invalidated the OTP after too many wrong codes
/// (`otp_invalidated`). The user must request a fresh code (restart the flow).
class OtpInvalidatedException extends AuthException {
  const OtpInvalidatedException(super.message);
}

/// Raised when resends are locked after the resend cap (`otp_resend_locked`).
/// [retryAfter] is how long until they're allowed again.
class OtpResendLockedException extends AuthException {
  const OtpResendLockedException(super.message, this.retryAfter);
  final Duration retryAfter;
}

/// The single entry point for authentication/registration data access.
///
/// View models talk only to this repository — never to an HTTP client directly.
/// It calls the Go backend's REST endpoints and maps responses/errors into
/// domain types. The backend delivers the code over SMS (Fast2SMS); when it
/// runs without provider credentials it accepts the fixed dev code
/// ([devOtp]) instead.
class AuthRepository {
  AuthRepository({http.Client? client, String? baseUrl, this._tokenGetter})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token synchronously from in-memory session state
  /// (wired to `AuthController`). Null when unauthenticated.
  final String? Function()? _tokenGetter;

  /// Dev one-time passcode shown as a hint on the OTP screen; the backend is
  /// the authority on whether a code is correct.
  static const String devOtp = '123456';

  /// Digits in a Sarthi OTP.
  static const int otpLength = 6;

  /// Requests an OTP be sent to [phoneE164].
  Future<void> requestOtp(String phoneE164) async {
    await _post('/auth/otp', {'phoneE164': phoneE164});
  }

  /// Re-sends the most recent OTP to [phoneE164]. The provider enforces its own
  /// resend window and attempt cap; a rejection surfaces as an [AuthException].
  Future<void> resendOtp(String phoneE164) async {
    await _post('/auth/otp/resend', {'phoneE164': phoneE164});
  }

  /// Verifies [code] for [phoneE164]; throws [AuthException] on a wrong code.
  ///
  /// Returns an [OtpResult]: for an already-registered number it carries a
  /// logged-in [AuthSession] (token + user); for a new number `registered` is
  /// false and the caller should collect a profile and [register].
  Future<OtpResult> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    final body = await _post('/auth/otp/verify', {
      'phoneE164': phoneE164,
      'code': code,
    });
    return OtpResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Creates the account and returns the logged-in [AuthSession] (token + user).
  Future<AuthSession> register({
    required String phoneE164,
    required String name,
    required String email,
    required DateTime dateOfBirth,
  }) async {
    final body = await _post('/auth/register', {
      'phoneE164': phoneE164,
      'name': name.trim(),
      'email': email.trim(),
      'dateOfBirth': _formatDate(dateOfBirth),
    });
    return AuthSession.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Revokes [token] on the server (best-effort logout). Local session state is
  /// cleared by the caller regardless of the outcome.
  Future<void> logout(String token) async {
    await _post('/auth/logout', const {}, token: token);
  }

  /// POSTs [payload] as JSON to [path]. Returns the response body on 2xx;
  /// throws [AuthException] with the server's message otherwise. Attaches a
  /// bearer token when one is supplied or available from [_tokenGetter].
  Future<String> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) async {
    final bearer = token ?? _tokenGetter?.call();
    final headers = {
      'Content-Type': 'application/json',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: headers,
        body: jsonEncode(payload),
      );
    } catch (_) {
      throw const AuthException(
        "Can't reach the server. Check your connection and try again.",
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw _exceptionFor(response);
  }

  /// Maps an error response to the most specific [AuthException] subtype using
  /// the backend's machine-readable `code`, so callers can branch on OTP
  /// rate-limit outcomes without string-matching messages.
  AuthException _exceptionFor(http.Response response) {
    final body = _decodeBody(response);
    final message = switch (body['error']) {
      final String m => m,
      _ => 'Something went wrong. Please try again.',
    };
    switch (body['code']) {
      case 'otp_incorrect':
        return OtpIncorrectException(message);
      case 'otp_invalidated':
        return OtpInvalidatedException(message);
      case 'otp_resend_locked':
        final seconds = body['retryAfterSeconds'];
        return OtpResendLockedException(
          message,
          Duration(seconds: seconds is int ? seconds : 0),
        );
      default:
        return AuthException(message);
    }
  }

  /// Decodes the JSON body as a map, or an empty map when it isn't one.
  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // fall through
    }
    return const {};
  }

  /// Formats a date as the backend's `YYYY-MM-DD` contract.
  static String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
