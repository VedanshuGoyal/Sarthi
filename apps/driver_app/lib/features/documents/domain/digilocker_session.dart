/// A DigiLocker session the backend opened for the Aadhaar check.
///
/// The driver signs in to DigiLocker at [url]; DigiLocker ends on
/// [redirectUrl], a page that only says to come back to the app. Whether it
/// worked is then read from the backend, never from what the page showed.
class DigiLockerSession {
  const DigiLockerSession({
    required this.url,
    this.redirectUrl,
    this.expiresAt,
  });

  final Uri url;
  final Uri? redirectUrl;
  final DateTime? expiresAt;

  factory DigiLockerSession.fromJson(Map<String, dynamic> json) {
    final redirect = json['redirectUrl'] as String?;
    final expires = json['expiresAt'] as String?;
    return DigiLockerSession(
      url: Uri.parse(json['url'] as String? ?? ''),
      redirectUrl: redirect == null || redirect.isEmpty
          ? null
          : Uri.tryParse(redirect),
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
    );
  }
}
