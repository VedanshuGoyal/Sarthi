import 'package:geolocator/geolocator.dart';

/// Outcome of an app-launch location permission request.
enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Thin data-layer wrapper around the `geolocator` plugin's permission APIs.
///
/// No business logic — just turns geolocator's service/permission checks into
/// a single [LocationPermissionResult] the app can act on.
class LocationService {
  const LocationService();

  /// Requests location permission, prompting the OS dialog if it hasn't been
  /// decided yet. Safe to call on every launch — geolocator no-ops and just
  /// reports the current status once a driver has already granted or
  /// permanently denied access.
  Future<LocationPermissionResult> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionResult.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationPermissionResult.granted,
      LocationPermission.deniedForever =>
        LocationPermissionResult.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationPermissionResult.denied,
    };
  }
}
