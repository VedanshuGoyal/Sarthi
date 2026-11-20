import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// The three OS grants the "Go Online" flow depends on, as the system
/// reports them right now. One that doesn't apply on this platform (the
/// overlay and battery settings exist only on Android) counts as granted,
/// as on the permissions step.
typedef PermissionGrants = ({
  bool overlay,
  bool backgroundLocation,
  bool battery,
});

/// Reads [PermissionGrants], or null when the OS can't be asked (web,
/// tests, a plugin error).
typedef PermissionGrantsSource = Future<PermissionGrants?> Function();

/// Asks the OS for the current grants without prompting for any. Lets the
/// Document View tick the permissions step for a driver who already
/// granted everything — before this install, or in system settings —
/// instead of making them open the step and tap Finish.
Future<PermissionGrants?> readPermissionGrants() async {
  if (kIsWeb) return null;
  try {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final background = await Permission.locationAlways.status;
    final overlay =
        !android || (await Permission.systemAlertWindow.status).isGranted;
    final battery =
        !android ||
        (await Permission.ignoreBatteryOptimizations.status).isGranted;
    return (
      overlay: overlay,
      backgroundLocation: background.isGranted,
      battery: battery,
    );
  } catch (_) {
    return null;
  }
}
