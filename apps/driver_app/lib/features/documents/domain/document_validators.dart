import '../../../l10n/l10n.dart';

/// Pure validation helpers for the document verification steps. Same shape as
/// the auth flow's `AuthValidators`: return a human-readable error, in the
/// app's language ([L10n.current]), or `null` when valid. No IO, so they're
/// trivially unit-testable.
abstract final class DocumentValidators {
  static final RegExp _aadhar = RegExp(r'^\d{12}$');
  static final RegExp _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _bankAccount = RegExp(r'^\d{9,18}$');

  static String? aadharNumber(String value) {
    final digits = value.trim();
    if (digits.isEmpty) return L10n.current.validationAadhaarEmpty;
    if (!_aadhar.hasMatch(digits)) {
      return L10n.current.validationAadhaarInvalid;
    }
    return null;
  }

  static String? drivingLicenseNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return L10n.current.validationLicenseEmpty;
    if (trimmed.length < 6) return L10n.current.validationLicenseInvalid;
    return null;
  }

  static String? bankAccountHolderName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return L10n.current.validationHolderNameEmpty;
    if (trimmed.length < 2) return L10n.current.validationNameTooShort;
    return null;
  }

  static String? bankAccountNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return L10n.current.validationAccountEmpty;
    if (!_bankAccount.hasMatch(trimmed)) {
      return L10n.current.validationAccountInvalid;
    }
    return null;
  }

  /// [accountNumber] is the value already entered in the first field.
  static String? confirmBankAccountNumber(String value, String accountNumber) {
    if (value.trim().isEmpty) return L10n.current.validationAccountConfirmEmpty;
    if (value.trim() != accountNumber.trim()) {
      return L10n.current.validationAccountMismatch;
    }
    return null;
  }

  static String? ifscCode(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return L10n.current.validationIfscEmpty;
    if (!_ifsc.hasMatch(trimmed)) return L10n.current.validationIfscInvalid;
    return null;
  }
}
