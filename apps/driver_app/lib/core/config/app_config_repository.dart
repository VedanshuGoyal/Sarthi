import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// The support number baked in at build time with
/// `--dart-define=SUPPORT_PHONE=+91…`, or empty. Never hard-code a number in
/// this public repo.
const String supportPhoneFromBuild = String.fromEnvironment('SUPPORT_PHONE');

/// Picks the support number to show: the backend's [fromConfig] when it has
/// one, else the build-time [fromBuild], else null (no "Contact support").
String? resolveSupportPhone({String? fromConfig, String fromBuild = ''}) {
  final config = fromConfig?.trim() ?? '';
  if (config.isNotEmpty) return config;
  final build = fromBuild.trim();
  return build.isEmpty ? null : build;
}

/// Reads the app's runtime settings from the backend's public
/// `GET /app/config` — today just the support number.
///
/// The view models (and the providers wrapping this) never talk HTTP
/// themselves. A failed or missing config is not an error: the build-time
/// fallback is used and nothing is thrown, so the UI only loses the button.
/// A successful read is kept for the rest of the app session; a failed one
/// is retried on the next call.
class AppConfigRepository {
  AppConfigRepository({
    http.Client? client,
    String? baseUrl,
    this._fallbackSupportPhone = supportPhoneFromBuild,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final String _fallbackSupportPhone;

  /// The backend's config, once read successfully.
  Map<String, dynamic>? _config;

  /// MOJUD support's WhatsApp number (E.164), or null when neither the
  /// backend nor the build provides one.
  Future<String?> supportPhone() async {
    final config = await _load();
    final fromConfig = config?['supportPhone'];
    return resolveSupportPhone(
      fromConfig: fromConfig is String ? fromConfig : null,
      fromBuild: _fallbackSupportPhone,
    );
  }

  Future<Map<String, dynamic>?> _load() async {
    final cached = _config;
    if (cached != null) return cached;
    try {
      final response = await _client.get(Uri.parse('$_baseUrl/app/config'));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return _config = decoded;
    } catch (_) {
      return null;
    }
  }
}
