import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/push_service.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import 'data/push_token_repository.dart';
import 'push_registration.dart';

/// Ride updates ("Driver assigned"). The id is the one the backend sends
/// (`ride_updates`); high importance makes them pop up with sound. Its name
/// and description, shown in the phone's notification settings, are in the
/// app's language when push starts; Android updates them on the next start
/// after a language change.
AndroidNotificationChannel rideUpdatesChannel() => AndroidNotificationChannel(
  'ride_updates',
  L10n.current.notifChannelName,
  description: L10n.current.notifChannelDescription,
  importance: Importance.high,
);

/// The app's one [PushService]. Overridden with [PushService.off] in tests.
final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(channel: rideUpdatesChannel());
});

/// Push registration for the signed-in customer, authenticated with the
/// current session token read on demand (like the other repositories).
final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  return PushRegistration(
    push: ref.watch(pushServiceProvider),
    repository: PushTokenRepository(
      client: ref.watch(backendClientProvider),
      tokenGetter: () => ref.read(authControllerProvider).valueOrNull?.token,
    ),
  );
});
