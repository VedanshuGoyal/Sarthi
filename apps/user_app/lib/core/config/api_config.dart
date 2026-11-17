import 'package:flutter/foundation.dart';

/// Where the Go backend lives, resolved per platform.
///
/// The Android emulator reaches the host machine at `10.0.2.2`, not
/// `localhost`; web and desktop/iOS simulators use `localhost`. Override with
/// `--dart-define=API_BASE_URL=...` to point at a deployed backend.
///
/// A release build must be given one: the local fallbacks are only for
/// debug and profile runs, and a release pointed at them would ship talking
/// to a loopback address. [ensureConfigured] stops such a build at startup.
abstract final class ApiConfig {
  static const String _override = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl => resolve(
    override: _override,
    release: kReleaseMode,
    web: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// Throws a [StateError] in a release build made without `API_BASE_URL`.
  /// Called first thing in `main`.
  static void ensureConfigured() => baseUrl;

  /// [baseUrl], with its inputs passed in for tests.
  @visibleForTesting
  static String resolve({
    required String override,
    required bool release,
    required bool web,
    required TargetPlatform platform,
  }) {
    if (override.isNotEmpty) return override;
    if (release) {
      throw StateError(
        'This release build has no API_BASE_URL. Build it with '
        'scripts/build-user-app-apk.sh, or pass '
        '--dart-define=API_BASE_URL=https://<api-domain>.',
      );
    }
    if (web) return 'http://localhost:8080';
    if (platform == TargetPlatform.android) return 'http://10.0.2.2:8080';
    return 'http://localhost:8080';
  }
}
