/// Pure validation helpers for the registration flow.
///
/// These return a human-readable error string, or `null` when the value is
/// valid — the shape the view models and text fields expect. Kept free of any
/// Flutter or IO dependency so they're trivially unit-testable.
abstract final class AuthValidators {
  /// Indian mobile numbers are 10 digits and start with 6–9.
  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');

  /// Pragmatic email check — good enough to catch typos without rejecting
  /// valid-but-unusual addresses.
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Validates the 10-digit national part of an Indian mobile number (no `+91`).
  static String? phoneNational(String value) {
    final digits = value.trim();
    if (digits.isEmpty) return 'Enter your mobile number';
    if (!_indianMobile.hasMatch(digits)) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  static String? name(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter your name';
    if (trimmed.length < 2) return 'Name is too short';
    return null;
  }

  static String? email(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(trimmed)) return 'Enter a valid email address';
    return null;
  }

  /// Minimum age (years) to register as a Sarthi customer.
  static const int minAge = 18;

  /// Validates the date of birth: it must be set, in the past, and at least
  /// [minAge] years ago.
  static String? dateOfBirth(DateTime? value) {
    if (value == null) return 'Select your date of birth';
    final now = DateTime.now();
    if (!value.isBefore(now)) return "Date of birth can't be in the future";
    final minBirthday = DateTime(value.year + minAge, value.month, value.day);
    if (minBirthday.isAfter(now)) {
      return 'You must be at least $minAge years old';
    }
    return null;
  }

  /// The OTP must be the expected number of digits. Whether it is *correct* is
  /// decided by the backend (here, the stubbed repository).
  static String? otp(String value, {required int length}) {
    final digits = value.trim();
    if (digits.length != length) return 'Enter the $length-digit code';
    if (!RegExp(r'^\d+$').hasMatch(digits)) return 'Code must be digits only';
    return null;
  }
}
