import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/l10n.dart';

/// Outcome of an app-launch location permission request.
enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// A point the device reported.
typedef DevicePosition = ({double lat, double lng});

/// One fix from a live position stream — heading is null when the device
/// can't tell which way it's pointing (e.g. standing still).
typedef DeviceFix = ({double lat, double lng, double? heading});

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

  /// A continuous stream of fixes, for sharing live location with a
  /// customer. On Android this runs as a foreground service — with its own
  /// persistent notification — so updates keep arriving while the driver is
  /// in another app (Google Maps for turn-by-turn). On platforms without
  /// that (web, desktop, iOS when backgrounded) the stream just does
  /// whatever the OS allows in the foreground; callers are expected to stop
  /// quietly if it goes silent rather than treat that as an error.
  Stream<DeviceFix> positionStream() {
    final settings = streamSettings(defaultTargetPlatform);
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => (
        lat: p.latitude,
        lng: p.longitude,
        // headingAccuracy is negative when the platform can't tell.
        heading: p.headingAccuracy >= 0 ? p.heading : null,
      ),
    );
  }

  /// The settings [positionStream] runs with on [platform].
  ///
  /// On Android the stream runs as geolocator's foreground service (type
  /// `location`, declared by the plugin's manifest) with a notification:
  ///
  ///  * a wake lock while it runs — without one the phone sleeps with the
  ///    screen off and the fixes arrive in a batch when it wakes, so the
  ///    customer sees the driver jump instead of move;
  ///  * the monochrome status-bar icon the push notifications use (the
  ///    launcher icon draws as a blank square there), on a channel named
  ///    for what it is in system settings.
  ///
  /// The notification's words are in the app's language ([L10n.current])
  /// at the time sharing starts.
  @visibleForTesting
  static LocationSettings streamSettings(TargetPlatform platform) {
    if (platform != TargetPlatform.android) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }
    final l10n = L10n.current;
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: l10n.locationSharingTitle,
        notificationText: l10n.locationSharingText,
        notificationChannelName: l10n.locationChannelName,
        notificationIcon: const AndroidResource(name: 'ic_stat_sarthi'),
        color: const Color(0xFF2A93BE),
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
}
