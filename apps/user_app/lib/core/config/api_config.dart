import 'package:flutter/foundation.dart';

/// Where the Go backend lives, resolved per platform.
///
/// The Android emulator reaches the host machine at `10.0.2.2`, not
/// `localhost`; web and desktop/iOS simulators use `localhost`. Override with
/// `--dart-define=API_BASE_URL=...` to point at a deployed backend.
abstract final class ApiConfig {
  static const String _override = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8080';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  /// Whether to show the "for testing, use 123456" hint on the OTP screen.
  ///
  /// The backend accepts the fixed dev code only when it runs without an SMS
  /// provider, so this defaults on for local dev. Build against a Fast2SMS-backed
  /// server with `--dart-define=SHOW_DEV_OTP_HINT=false` to hide it.
  static const bool showDevOtpHint = bool.fromEnvironment(
    'SHOW_DEV_OTP_HINT',
    defaultValue: true,
  );
}
