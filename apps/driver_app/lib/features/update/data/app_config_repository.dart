import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/config/app_build.dart';
import '../domain/app_release.dart';

/// Reads the backend's client compatibility contract (`GET /app/config`):
/// the oldest build of this app it still serves, the newest published, and
/// where to download it.
class AppConfigRepository {
  AppConfigRepository({
    required this._client,
    String? baseUrl,
    this._app = AppBuild.app,
  }) : _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final String _app;

  /// This app's entry, or null when the backend doesn't list it. Throws on
  /// a network failure or an unreadable reply; callers treat any failure as
  /// "nothing to enforce".
  Future<AppRelease?> fetch() async {
    final response = await _client.get(Uri.parse('$_baseUrl/app/config'));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'GET /app/config answered ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    final apps = body['apps'];
    if (apps is! Map<String, dynamic>) return null;
    final entry = apps[_app];
    if (entry is! Map<String, dynamic>) return null;
    return AppRelease.fromJson(entry);
  }
}
