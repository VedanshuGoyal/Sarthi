import 'package:checks/checks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/config/api_config.dart';

void main() {
  String resolve({
    String override = '',
    bool release = false,
    bool web = false,
    TargetPlatform platform = TargetPlatform.android,
  }) => ApiConfig.resolve(
    override: override,
    release: release,
    web: web,
    platform: platform,
  );

  test('a release build without API_BASE_URL refuses to start', () {
    check(() => resolve(release: true)).throws<StateError>();
    check(
      resolve(release: true, override: 'https://api.mojud.life'),
    ).equals('https://api.mojud.life');
  });

  test('debug runs fall back to the local backend', () {
    check(resolve()).equals('http://10.0.2.2:8080');
    check(resolve(web: true)).equals('http://localhost:8080');
    check(
      resolve(platform: TargetPlatform.iOS),
    ).equals('http://localhost:8080');
    check(resolve(override: 'http://lan:8080')).equals('http://lan:8080');
  });

  test('the test build itself is configured', () {
    check(ApiConfig.ensureConfigured).returnsNormally();
  });
}
