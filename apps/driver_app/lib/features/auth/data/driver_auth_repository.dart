import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/driver_auth_session.dart';

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

/// Raised when the account can't be deleted yet (`account_busy`): a ride is
/// underway, or a completed ride's customer hasn't paid. [message] is the
/// server's explanation.
class AccountBusyException extends AuthException {
  const AccountBusyException(super.message);
}

/// Raised when the server no longer accepts the session (401). The app's
/// HTTP client signs the driver out when it sees one.
class SessionExpiredException extends AuthException {
  const SessionExpiredException(super.message);
}

/// The single entry point for driver authentication/registration data access.
///
/// View models talk only to this repository — never to an HTTP client
/// directly. It calls the Go backend's `/driver/auth/*` endpoints and maps
/// responses/errors into domain types. The backend delivers the code over SMS
/// (Fast2SMS); when it runs without provider credentials it accepts the fixed
/// dev code ([devOtp]) instead.
class DriverAuthRepository {
  DriverAuthRepository({
    http.Client? client,
    String? baseUrl,
    this._tokenGetter,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token synchronously from in-memory session state
  /// (wired to `DriverAuthController`). Null when unauthenticated.
  final String? Function()? _tokenGetter;

  /// Dev one-time passcode shown as a hint on the OTP screen; the backend is
  /// the authority on whether a code is correct.
  static const String devOtp = '123456';

  /// Digits in a Sarthi OTP.
  static const int otpLength = 6;

  /// Requests an OTP be sent to [phoneE164].
  Future<void> requestOtp(String phoneE164) async {
    await _post('/driver/auth/otp', {'phoneE164': phoneE164});
  }

  /// Re-sends the most recent OTP to [phoneE164]. The provider enforces its own
  /// resend window and attempt cap; a rejection surfaces as an [AuthException].
  Future<void> resendOtp(String phoneE164) async {
    await _post('/driver/auth/otp/resend', {'phoneE164': phoneE164});
  }

  /// Verifies [code] for [phoneE164]; throws [AuthException] on a wrong code.
  ///
  /// Returns a [DriverOtpResult]: for an already-registered number it carries
  /// a logged-in [DriverAuthSession] (token + driver); for a new number
  /// `registered` is false and the caller should collect a name and [register].
  Future<DriverOtpResult> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    final body = await _post('/driver/auth/otp/verify', {
      'phoneE164': phoneE164,
      'code': code,
    });
    return DriverOtpResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Creates the driver account and returns the logged-in [DriverAuthSession]
  /// (token + driver). [consentVersion] is the version of the Terms and
  /// Privacy Policy the driver agreed to, which the server records.
  /// [registrationTicket] is [DriverOtpResult.registrationTicket] from
  /// verifying the number: the server needs it from this build on.
  Future<DriverAuthSession> register({
    required String phoneE164,
    required String name,
    String? consentVersion,
    String? registrationTicket,
  }) async {
    final body = await _post('/driver/auth/register', {
      'phoneE164': phoneE164,
      'name': name.trim(),
      'consentVersion': ?consentVersion,
      'registrationTicket': ?registrationTicket,
    });
    return DriverAuthSession.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Revokes [token] on the server (best-effort logout). Local session state is
  /// cleared by the caller regardless of the outcome.
  Future<void> logout(String token) async {
    await _post('/driver/auth/logout', const {}, token: token);
  }

  /// Deletes the signed-in driver's account (`DELETE /driver/account`).
  ///
  /// The server anonymises the account, deletes their KYC documents, bank
  /// details and checks, and revokes every session; ride and payment
  /// records stay. Throws [AccountBusyException] while it can't yet,
  /// [SessionExpiredException] on a 401, and [AuthException] otherwise.
  Future<void> deleteAccount() async {
    await _send('DELETE', '/driver/account');
  }

  /// POSTs [payload] as JSON to [path]; see [_send].
  Future<String> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) => _send('POST', path, payload: payload, token: token);

  /// Sends [method] to [path], with [payload] as its JSON body. Returns the
  /// response body on 2xx; throws [AuthException] with the server's message
  /// otherwise. Attaches a bearer token when one is supplied or available
  /// from [_tokenGetter].
  Future<String> _send(
    String method,
    String path, {
    Map<String, dynamic>? payload,
    String? token,
  }) async {
    final bearer = token ?? _tokenGetter?.call();
    final headers = {
      'Content-Type': 'application/json',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };
    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = method == 'DELETE'
          ? await _client.delete(uri, headers: headers)
          : await _client.post(
              uri,
              headers: headers,
              body: jsonEncode(payload ?? const {}),
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
      case 'account_busy':
        return AccountBusyException(message);
    }
    // A 401 without a code is the session check (OTP 401s carry one).
    if (response.statusCode == 401 && body['code'] == null) {
      return const SessionExpiredException(
        'Your session has ended. Please sign in again.',
      );
    }
    return AuthException(message);
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
}
