/// The legal documents a driver agrees to when registering, and which
/// version of them.
///
/// [consentVersion] is sent with `POST /driver/auth/register` so the backend
/// records what was agreed to and when. Bump it whenever the Terms or the
/// Privacy Policy change in a way that needs fresh agreement.
abstract final class Legal {
  /// The version of the Terms and Privacy Policy shown at registration.
  static const String consentVersion = '2026-11';

  /// MOJUD's Terms of Service.
  static final Uri termsUrl = Uri.parse('https://apps.mojud.life/terms');

  /// MOJUD's Privacy Policy.
  static final Uri privacyUrl = Uri.parse('https://apps.mojud.life/privacy');
}
