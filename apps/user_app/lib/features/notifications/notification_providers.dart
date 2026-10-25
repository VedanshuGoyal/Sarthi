import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/push_service.dart';
import '../auth/auth_controller.dart';
import 'data/push_token_repository.dart';
import 'push_registration.dart';

/// Ride updates ("Driver assigned"). The id is the one the backend sends
/// (`ride_updates`); high importance makes them pop up with sound.
const rideUpdatesChannel = AndroidNotificationChannel(
  'ride_updates',
  'Ride updates',
  description: 'Your driver is assigned, and other changes to your rides.',
  importance: Importance.high,
);

/// The app's one [PushService]. Overridden with [PushService.off] in tests.
final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(channel: rideUpdatesChannel);
});

/// Push registration for the signed-in customer, authenticated with the
/// current session token read on demand (like the other repositories).
final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  return PushRegistration(
    push: ref.watch(pushServiceProvider),
    repository: PushTokenRepository(
      tokenGetter: () => ref.read(authControllerProvider).valueOrNull?.token,
    ),
  );
});
