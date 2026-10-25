import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A push notification's routing data, as the backend sends it: what
/// happened (`ride_request`, `driver_assigned`) and to which ride.
@immutable
class PushEvent {
  const PushEvent({required this.type, this.rideId});

  /// Reads the data payload of an FCM message or a local notification.
  factory PushEvent.fromData(Map<String, dynamic> data) => PushEvent(
    type: data['type'] as String? ?? '',
    rideId: data['rideId'] as String?,
  );

  final String type;
  final String? rideId;
}

/// The device side of push notifications: Firebase Cloud Messaging plus
/// local notifications for the Android channel and for messages that arrive
/// while the app is open (FCM shows nothing then on its own).
///
/// Targets are FCM registration tokens — what the backend's HTTP v1 send
/// takes. firebase_messaging 17 marks the token calls deprecated in favour of
/// Installation-ID direct send; they still work, and moving over means
/// changing the backend's send target too.
///
/// Android only. Push stays off — every call a quiet no-op — on web, in tests
/// ([PushService.off]), and in builds without `android/app/
/// google-services.json`, where Firebase has no project to start with.
class PushService {
  PushService({required this.channel}) : _enabled = true;

  /// A service that never starts (tests, previews).
  PushService.off()
    : channel = const AndroidNotificationChannel('off', 'off'),
      _enabled = false;

  /// The channel this app's notifications use. Its id must match the one the
  /// backend sends; its importance makes them pop up with sound.
  final AndroidNotificationChannel channel;

  final bool _enabled;

  static const String _icon = 'ic_stat_sarthi';
  static const Color _accent = Color(0xFF2A93BE);

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final StreamController<PushEvent> _taps = StreamController.broadcast();
  final StreamController<PushEvent> _arrivals = StreamController.broadcast();
  Future<bool>? _ready;
  PushEvent? _launchTap;

  /// Notifications the user tapped while the app was running or in the
  /// background.
  Stream<PushEvent> get taps => _taps.stream;

  /// Messages that arrived while the app was in the foreground, so screens
  /// can refresh straight away rather than on their next poll.
  Stream<PushEvent> get arrivals => _arrivals.stream;

  /// Starts Firebase once and reports whether push is available.
  Future<bool> get ready => _ready ??= _start();

  /// The notification that launched the app from closed, if any. Returned
  /// once.
  Future<PushEvent?> takeLaunchTap() async {
    if (!await ready) return null;
    final tap = _launchTap;
    _launchTap = null;
    return tap;
  }

  /// Asks for permission to notify (Android 13+ shows the prompt once) and
  /// returns this install's token, or null when push is unavailable.
  Future<String?> token() async {
    if (!await ready) return null;
    try {
      await FirebaseMessaging.instance.requestPermission();
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('push: no token ($e)');
      return null;
    }
  }

  /// New tokens FCM issues for this install (rare: restore, data cleared).
  Stream<String> tokenRefreshes() async* {
    if (!await ready) return;
    // ignore: deprecated_member_use
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }

  /// Invalidates this install's token (sign-out), so nothing more reaches it.
  Future<void> deleteToken() async {
    if (!await ready) return;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('push: deleting token failed ($e)');
    }
  }

  Future<bool> _start() async {
    if (!_enabled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('push: off — Firebase is not configured ($e)');
      return false;
    }
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
        ),
        onDidReceiveNotificationResponse: (response) {
          final tap = _decode(response.payload);
          if (tap != null) _taps.add(tap);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      FirebaseMessaging.onMessage.listen(_showInForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _taps.add(PushEvent.fromData(m.data)),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _launchTap = PushEvent.fromData(initial.data);
      } else {
        final launch = await _local.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          _launchTap = _decode(launch!.notificationResponse?.payload);
        }
      }
      return true;
    } catch (e) {
      debugPrint('push: off — setup failed ($e)');
      return false;
    }
  }

  /// FCM leaves foreground messages to the app: show them like the system
  /// would, on the same channel, and tell listening screens.
  Future<void> _showInForeground(RemoteMessage message) async {
    final event = PushEvent.fromData(message.data);
    _arrivals.add(event);
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      id: (event.rideId ?? message.messageId ?? n.title ?? '').hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.high,
          icon: _icon,
          color: _accent,
          styleInformation: BigTextStyleInformation(n.body ?? ''),
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static PushEvent? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload);
      return data is Map<String, dynamic> ? PushEvent.fromData(data) : null;
    } catch (_) {
      return null;
    }
  }
}
