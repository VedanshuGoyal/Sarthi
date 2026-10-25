import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/push_service.dart';
import 'data/push_token_repository.dart';

/// Keeps this install registered for the signed-in account's notifications:
/// on [start] it asks for permission and sends the device token to the
/// backend (and again whenever FCM rotates it); on [stop], before sign-out,
/// it withdraws the token so the next account on this phone starts clean.
///
/// Best-effort throughout — a failure here never blocks the app, it just
/// means no pushes until the next start.
class PushRegistration {
  PushRegistration({required this._push, required this._repository});

  final PushService _push;
  final PushTokenRepository _repository;

  StreamSubscription<String>? _refreshes;
  String? _token;

  /// Registers this install. Safe to call on every sign-in.
  Future<void> start() async {
    final token = await _push.token();
    if (token == null) return;
    _token = token;
    await _save(token);
    _refreshes ??= _push.tokenRefreshes().listen((fresh) {
      _token = fresh;
      _save(fresh);
    });
  }

  /// Withdraws this install's token. Call while the session is still valid.
  Future<void> stop() async {
    await _refreshes?.cancel();
    _refreshes = null;
    final token = _token;
    _token = null;
    if (token != null) {
      try {
        await _repository.delete(token);
      } on PushTokenException catch (e) {
        debugPrint('push: unregistering failed (${e.message})');
      }
    }
    await _push.deleteToken();
  }

  Future<void> _save(String token) async {
    try {
      await _repository.save(token);
    } on PushTokenException catch (e) {
      debugPrint('push: registering failed (${e.message})');
    }
  }
}
