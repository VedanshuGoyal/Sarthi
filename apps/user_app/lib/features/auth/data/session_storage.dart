import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_session.dart';

/// Durable, encrypted persistence for the logged-in [AuthSession].
///
/// This is the *disk* half of session management (the memory half lives in
/// `AuthController`). It's an interface so tests can swap in a fake without the
/// platform channel that `flutter_secure_storage` needs.
abstract interface class SessionStorage {
  /// Reads the persisted session, or null if none / unreadable.
  Future<AuthSession?> read();

  /// Persists [session], replacing any previous one.
  Future<void> write(AuthSession session);

  /// Removes the persisted session (logout).
  Future<void> clear();
}

/// [SessionStorage] backed by the OS keychain / keystore via
/// `flutter_secure_storage`.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Key under which the session JSON is stored.
  static const String _sessionKey = 'sarthi.auth.session';

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt / outdated payload — treat as logged out and clear it.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
