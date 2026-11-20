import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/app_language.dart';

/// The customer's app-language choice, saved on this phone. It's a device
/// setting: it outlives sign-out and isn't sent to the backend.
abstract interface class LanguageRepository {
  /// The saved choice, or [AppLanguage.system] when none (or unreadable).
  Future<AppLanguage> read();

  Future<void> write(AppLanguage language);
}

/// [LanguageRepository] in the OS keystore, beside the app's other local
/// settings (the session, saved cars, recent pickups).
class SecureLanguageRepository implements LanguageRepository {
  SecureLanguageRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _key = 'sarthi.user.language';

  @override
  Future<AppLanguage> read() async {
    try {
      return AppLanguage.fromStorage(await _storage.read(key: _key));
    } catch (_) {
      // No keystore (tests, a broken plugin): follow the phone.
      return AppLanguage.system;
    }
  }

  @override
  Future<void> write(AppLanguage language) =>
      _storage.write(key: _key, value: language.storageValue);
}
