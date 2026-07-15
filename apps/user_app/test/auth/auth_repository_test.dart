import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';

/// A client that answers every request with [status] and [body].
http.Client _clientReturning(int status, Map<String, dynamic> body) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

/// Runs [future] and returns the object it throws, failing if it completes.
Future<Object> _capture(Future<void> future) async {
  try {
    await future;
  } catch (e) {
    return e;
  }
  throw StateError('expected the future to throw');
}

void main() {
  group('AuthRepository error mapping', () {
    test('otp_incorrect maps to OtpIncorrectException', () async {
      final repo = AuthRepository(
        client: _clientReturning(401, {
          'error': 'incorrect verification code',
          'code': 'otp_incorrect',
        }),
      );

      await check(
        repo.verifyOtp(phoneE164: '+919876543210', code: '000000'),
      ).throws<OtpIncorrectException>();
    });

    test('otp_invalidated maps to OtpInvalidatedException', () async {
      final repo = AuthRepository(
        client: _clientReturning(429, {
          'error': 'too many incorrect attempts; request a new code',
          'code': 'otp_invalidated',
        }),
      );

      await check(
        repo.verifyOtp(phoneE164: '+919876543210', code: '000000'),
      ).throws<OtpInvalidatedException>();
    });

    test('otp_resend_locked maps to OtpResendLockedException with retryAfter', () async {
      final repo = AuthRepository(
        client: _clientReturning(429, {
          'error': 'too many code requests; try again in 30 minutes or restart',
          'code': 'otp_resend_locked',
          'retryAfterSeconds': 1800,
        }),
      );

      final error = await _capture(repo.resendOtp('+919876543210'));
      check(error)
          .isA<OtpResendLockedException>()
          .has((e) => e.retryAfter, 'retryAfter')
          .equals(const Duration(seconds: 1800));
    });

    test('an unrecognised error falls back to a plain AuthException', () async {
      final repo = AuthRepository(
        client: _clientReturning(500, {'error': 'boom'}),
      );

      final error = await _capture(repo.resendOtp('+919876543210'));
      // A bare AuthException, not one of the OTP subtypes.
      check(error).isA<AuthException>().has((e) => e.message, 'message').equals('boom');
      check(error).not((it) => it.isA<OtpResendLockedException>());
    });
  });
}
