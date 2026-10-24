import 'package:geolocator/geolocator.dart';

/// Outcome of an app-launch location permission request.
enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// A point the device reported.
typedef DevicePosition = ({double lat, double lng});

/// Thin data-layer wrapper around the `geolocator` plugin.
///
/// No business logic — just turns geolocator's service/permission checks into
/// a single [LocationPermissionResult], and reads the current position.
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

  /// The device's position, or null when permission is missing, location is
  /// off, or no fix arrives within [timeout]. Falls back to the last known
  /// fix rather than leaving a driver with no distance at all.
  Future<DevicePosition?> currentPosition({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(timeLimit: timeout),
      );
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last == null ? null : (lat: last.latitude, lng: last.longitude);
      } catch (_) {
        return null; // getLastKnownPosition is unsupported on web
      }
    }
  }
}
