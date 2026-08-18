import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/driver_auth_session.dart';

/// Durable, encrypted persistence for the logged-in [DriverAuthSession].
///
/// This is the *disk* half of session management (the memory half lives in
/// `DriverAuthController`). It's an interface so tests can swap in a fake
/// without the platform channel that `flutter_secure_storage` needs.
abstract interface class DriverSessionStorage {
  /// Reads the persisted session, or null if none / unreadable.
  Future<DriverAuthSession?> read();

  /// Persists [session], replacing any previous one.
  Future<void> write(DriverAuthSession session);

  /// Removes the persisted session (logout).
  Future<void> clear();
}

/// [DriverSessionStorage] backed by the OS keychain / keystore via
/// `flutter_secure_storage`.
class SecureDriverSessionStorage implements DriverSessionStorage {
  SecureDriverSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Key under which the session JSON is stored.
  static const String _sessionKey = 'sarthi.driver.auth.session';

  @override
  Future<DriverAuthSession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return DriverAuthSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Corrupt / outdated payload — treat as logged out and clear it.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(DriverAuthSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
