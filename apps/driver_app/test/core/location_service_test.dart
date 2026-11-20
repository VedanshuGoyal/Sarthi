import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/core/services/location_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('live location stream settings', () {
    test('on Android, a foreground service that keeps the phone awake', () {
      final settings = LocationService.streamSettings(TargetPlatform.android);

      check(settings).isA<AndroidSettings>();
      final config = (settings as AndroidSettings).foregroundNotificationConfig;
      check(config).isNotNull();
      check(config!.enableWakeLock).isTrue();
      check(config.setOngoing).isTrue();
      check(config.notificationChannelName).equals('Live location');
      check(config.notificationIcon.name).equals('ic_stat_sarthi');
      check(config.notificationIcon.defType).equals('drawable');
      check(settings.intervalDuration).equals(const Duration(seconds: 10));
    });

    test('elsewhere, plain settings', () {
      final settings = LocationService.streamSettings(TargetPlatform.iOS);

      check(settings).not((s) => s.isA<AndroidSettings>());
      check(settings.distanceFilter).equals(10);
    });

    // geolocator finds the icon by name at run time: one that's missing, or
    // stripped by release resource shrinking, breaks the notification.
    test('the notification icon ships, and survives resource shrinking', () {
      const res = 'android/app/src/main/res';
      check(File('$res/drawable/ic_stat_sarthi.xml').existsSync()).isTrue();
      check(
        File('$res/raw/keep.xml').readAsStringSync(),
      ).contains('@drawable/ic_stat_sarthi');
    });

    test('the manifest lets the service hold its wake lock', () {
      check(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      ).contains('android.permission.WAKE_LOCK');
    });
  });
}
