/// Which build of which app this is, for the backend's client compatibility
/// contract: every backend request carries [headers], and a build the server
/// no longer serves is answered 426 `update_required`.
abstract final class AppBuild {
  /// This app's id, as sent in `X-App` and keyed in `GET /app/config`.
  static const String app = 'driver_app';

  /// The build number: the `+N` of pubspec's version, passed in by
  /// `scripts/build-driver-app-apk.sh` as `--dart-define=APP_BUILD=N`. 0 for a
  /// debug run or any build made without it, which is never turned away.
  static const int number = int.fromEnvironment('APP_BUILD', defaultValue: 0);

  /// The headers every request to the MOJUD backend carries.
  static const Map<String, String> headers = {
    'X-App': app,
    'X-Build': '$number',
  };

  /// Where the APKs are published, until `GET /app/config` says otherwise.
  static const String defaultDownloadUrl = 'https://apps.mojud.life';
}
