/// Pure validation helpers for the document verification steps. Same shape as
/// the auth flow's `AuthValidators`: return a human-readable error, or `null`
/// when valid. No Flutter/IO dependency so they're trivially unit-testable.
abstract final class DocumentValidators {
  static final RegExp _aadhar = RegExp(r'^\d{12}$');
  static final RegExp _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _bankAccount = RegExp(r'^\d{9,18}$');

  static String? aadharNumber(String value) {
    final digits = value.trim();
    if (digits.isEmpty) return 'Enter your Aadhar number';
    if (!_aadhar.hasMatch(digits)) {
      return 'Enter a valid 12-digit Aadhar number';
    }
    return null;
  }

  static String? drivingLicenseNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter your driving license number';
    if (trimmed.length < 6) return 'Enter a valid license number';
    return null;
  }

  static String? bankAccountHolderName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter the account holder\'s name';
    if (trimmed.length < 2) return 'Name is too short';
    return null;
  }

  static String? bankAccountNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter your account number';
    if (!_bankAccount.hasMatch(trimmed)) return 'Enter a valid account number';
    return null;
  }

  /// [accountNumber] is the value already entered in the first field.
  static String? confirmBankAccountNumber(String value, String accountNumber) {
    if (value.trim().isEmpty) return 'Re-enter your account number';
    if (value.trim() != accountNumber.trim()) {
      return 'Account numbers don\'t match';
    }
    return null;
  }

  static String? ifscCode(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return 'Enter the IFSC code';
    if (!_ifsc.hasMatch(trimmed)) return 'Enter a valid IFSC code';
    return null;
  }
}
