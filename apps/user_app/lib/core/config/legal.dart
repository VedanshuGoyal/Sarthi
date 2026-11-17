/// The legal documents a customer agrees to when they open an account, and
/// the version of them the server records with the consent.
abstract final class Legal {
  /// Sent as `consentVersion` on registration. Change it whenever the Terms
  /// or the Privacy Policy change, so the server knows who agreed to which.
  static const String consentVersion = '2026-11';

  static final Uri termsUrl = Uri.parse('https://apps.mojud.life/terms');
  static final Uri privacyUrl = Uri.parse('https://apps.mojud.life/privacy');
}
