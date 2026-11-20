import '../../../l10n/l10n.dart';

/// Pure validation helpers for the driver registration flow.
///
/// These return a human-readable error string in the app's language (via
/// [L10n.current]), or `null` when the value is valid — the shape the view
/// model and text fields expect. Free of IO, so they're trivially
/// unit-testable.
abstract final class AuthValidators {
  /// Indian mobile numbers are 10 digits and start with 6–9.
  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');

  /// Validates the 10-digit national part of an Indian mobile number (no `+91`).
  static String? phoneNational(String value) {
    final digits = value.trim();
    if (digits.isEmpty) return L10n.current.authPhoneRequired;
    if (!_indianMobile.hasMatch(digits)) {
      return L10n.current.authPhoneInvalid;
    }
    return null;
  }

  static String? name(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return L10n.current.authNameRequired;
    if (trimmed.length < 2) return L10n.current.authNameTooShort;
    return null;
  }

  /// The OTP must be the expected number of digits. Whether it is *correct* is
  /// decided by the backend.
  static String? otp(String value, {required int length}) {
    final digits = value.trim();
    if (digits.length != length) return L10n.current.otpWrongLength(length);
    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return L10n.current.otpDigitsOnly;
    }
    return null;
  }
}
