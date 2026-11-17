import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/driver_auth_controller.dart';
import '../auth/driver_auth_providers.dart';
import '../notifications/notification_providers.dart';

/// Signs the driver out of this phone: stops its ride notifications and
/// revokes the session server-side (both best-effort, so a dead network
/// can't trap anyone signed in), then clears it locally, which returns the
/// app to the start screen.
///
/// Going off duty first is the caller's job; a driver still on the
/// Document View was never on duty.
Future<void> signOutDriver(WidgetRef ref) async {
  await ref
      .read(pushRegistrationProvider)
      .stop()
      .timeout(const Duration(seconds: 5), onTimeout: () {});
  final auth = ref.read(driverAuthControllerProvider.notifier);
  final token = auth.token;
  if (token != null) {
    try {
      await ref.read(driverAuthRepositoryProvider).logout(token);
    } catch (_) {
      // Clearing locally regardless; a failed revoke mustn't trap the driver.
    }
  }
  await auth.signOut();
}
