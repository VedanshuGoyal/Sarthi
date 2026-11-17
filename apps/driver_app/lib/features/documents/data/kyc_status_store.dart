import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/driver_kyc.dart';

/// Remembers the last KYC status the backend gave this phone's driver, so a
/// cold start without network still opens Home for a driver who was
/// verified, instead of a Document View they can't get past.
///
/// It's only a hint for the app's gate. The backend checks verification on
/// every ride action, and the next successful load replaces it.
abstract interface class KycStatusStore {
  /// The status last stored for [driverId], or null if none (or it was
  /// stored for another driver).
  Future<KycStatus?> read(String driverId);

  /// Stores [status] for [driverId], replacing any other driver's.
  Future<void> write(String driverId, KycStatus status);
}

/// [KycStatusStore] in the OS keystore, beside the session.
class SecureKycStatusStore implements KycStatusStore {
  SecureKycStatusStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _key = 'sarthi.driver.kyc.status';

  @override
  Future<KycStatus?> read(String driverId) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final split = raw.lastIndexOf(':');
    if (split < 0 || raw.substring(0, split) != driverId) return null;
    final name = raw.substring(split + 1);
    return KycStatus.values.where((s) => s.name == name).firstOrNull;
  }

  @override
  Future<void> write(String driverId, KycStatus status) =>
      _storage.write(key: _key, value: '$driverId:${status.name}');
}
