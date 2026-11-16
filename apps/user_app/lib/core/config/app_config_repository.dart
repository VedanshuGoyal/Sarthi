import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// The support number this build was given with
/// `--dart-define=SUPPORT_PHONE=+91…`, or empty. Never written in the source:
/// this repository is public.
const String supportPhoneFromEnvironment = String.fromEnvironment(
  'SUPPORT_PHONE',
);

/// The support number to offer, from the server's config first and this
/// build's [fallback] second, normalised to `+<digits>`; null when neither
/// holds a plausible number (the "Contact support" button then hides).
String? resolveSupportPhone(
  String? fromConfig, {
  String fallback = supportPhoneFromEnvironment,
}) => _normalisePhone(fromConfig) ?? _normalisePhone(fallback);

String? _normalisePhone(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 10 && digits.length <= 15 ? '+$digits' : null;
}

/// Settings the server hands every install (`GET /app/config`): today just
/// the support number. Read once per app session; any failure — an older
/// server without the endpoint, no network — counts as "not configured",
/// never as an error the screens have to handle.
class AppConfigRepository {
  AppConfigRepository({
    http.Client? client,
    String? baseUrl,
    this.fallbackSupportPhone = supportPhoneFromEnvironment,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Used when the server names no support number.
  final String fallbackSupportPhone;

  Future<String?>? _supportPhone;

  /// The support number to show, or null to hide the button. Cached after
  /// the first call.
  Future<String?> supportPhone() =>
      _supportPhone ??= _fetchConfiguredPhone().then(
        (configured) =>
            resolveSupportPhone(configured, fallback: fallbackSupportPhone),
      );

  Future<String?> _fetchConfiguredPhone() async {
    try {
      final response = await _client.get(Uri.parse('$_baseUrl/app/config'));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      return switch (body) {
        {'supportPhone': final String phone} => phone,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}
