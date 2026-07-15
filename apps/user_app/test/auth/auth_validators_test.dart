import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/auth/domain/auth_validators.dart';

void main() {
  group('AuthValidators.phoneNational', () {
    test('accepts a valid 10-digit Indian mobile', () {
      check(AuthValidators.phoneNational('9876543210')).isNull();
    });

    test('rejects empty, short, and out-of-range numbers', () {
      check(AuthValidators.phoneNational('')).isNotNull();
      check(AuthValidators.phoneNational('98765')).isNotNull();
      // Indian mobiles start 6–9.
      check(AuthValidators.phoneNational('1234567890')).isNotNull();
    });
  });

  group('AuthValidators.name', () {
    test('accepts a real name and trims whitespace', () {
      check(AuthValidators.name('  Asha  ')).isNull();
    });

    test('rejects empty or single-character names', () {
      check(AuthValidators.name('')).isNotNull();
      check(AuthValidators.name('A')).isNotNull();
    });
  });

  group('AuthValidators.email', () {
    test('accepts a well-formed address', () {
      check(AuthValidators.email('asha@example.com')).isNull();
    });

    test('rejects malformed addresses', () {
      check(AuthValidators.email('asha')).isNotNull();
      check(AuthValidators.email('asha@')).isNotNull();
      check(AuthValidators.email('asha@example')).isNotNull();
    });
  });

  group('AuthValidators.dateOfBirth', () {
    test('accepts an adult born well in the past', () {
      check(AuthValidators.dateOfBirth(DateTime(2000, 1, 1))).isNull();
    });

    test('rejects a missing date, the future, and under-18', () {
      final now = DateTime.now();
      check(AuthValidators.dateOfBirth(null)).isNotNull();
      check(
        AuthValidators.dateOfBirth(now.add(const Duration(days: 1))),
      ).isNotNull();
      check(AuthValidators.dateOfBirth(DateTime(now.year - 5))).isNotNull();
    });
  });

  group('AuthValidators.otp', () {
    test('accepts exactly the expected number of digits', () {
      check(AuthValidators.otp('123456', length: 6)).isNull();
    });

    test('rejects wrong length or non-digits', () {
      check(AuthValidators.otp('123', length: 6)).isNotNull();
      check(AuthValidators.otp('12345a', length: 6)).isNotNull();
    });
  });
}
