import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/location_service.dart';

/// Single shared [LocationService] instance.
final locationServiceProvider = Provider<LocationService>((ref) {
  return const LocationService();
});

/// Fires the OS location-permission prompt as soon as something watches it.
///
/// Watched from the app root so the request happens at launch, in parallel
/// with auth-session hydration — it never blocks navigation. `keepAlive` so
/// the request (and its result) survives even if the watching widget rebuilds
/// away before the driver answers the OS prompt.
final locationPermissionProvider = FutureProvider<LocationPermissionResult>((
  ref,
) {
  ref.keepAlive();
  return ref.watch(locationServiceProvider).requestPermission();
});
