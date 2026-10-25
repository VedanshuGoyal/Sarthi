import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/push_service.dart';
import '../auth/driver_auth_controller.dart';
import 'data/push_token_repository.dart';
import 'push_registration.dart';

/// New ride requests near the driver. The id is the one the backend sends
/// (`ride_requests`); max importance makes them pop up over other apps with
/// sound, like a cab app's ride ping.
const rideRequestsChannel = AndroidNotificationChannel(
  'ride_requests',
  'Ride requests',
  description: 'New rides booked near you while you are on duty.',
  importance: Importance.max,
);

/// The app's one [PushService]. Overridden with [PushService.off] in tests.
final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(channel: rideRequestsChannel);
});

/// Push registration for the signed-in driver, authenticated with the
/// current session token read on demand (like the other repositories).
final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  return PushRegistration(
    push: ref.watch(pushServiceProvider),
    repository: PushTokenRepository(
      tokenGetter: () =>
          ref.read(driverAuthControllerProvider).valueOrNull?.token,
    ),
  );
});
