import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/car.dart';

/// Durable on-device persistence for the customer's saved cars.
///
/// An interface so tests can swap in a fake without the platform channel that
/// `flutter_secure_storage` needs. Ordered newest-first, matching how the
/// repository writes it.
abstract interface class SavedCarsStorage {
  /// Reads the saved cars, or an empty list if none / unreadable.
  Future<List<Car>> read();

  /// Persists [cars], replacing any previous list.
  Future<void> write(List<Car> cars);
}

/// [SavedCarsStorage] backed by the OS keychain / keystore via
/// `flutter_secure_storage` — a registration plate identifies the customer's
/// vehicle, so it rides the same secure store as the auth session and the
/// pickup history rather than plain preferences.
class SecureSavedCarsStorage implements SavedCarsStorage {
  /// [userId] is the signed-in customer's: each account on this phone gets
  /// its own list, so the next one to sign in never sees — or books with —
  /// the last one's cars (reads are served from here, not the server).
  SecureSavedCarsStorage({FlutterSecureStorage? storage, String? userId})
    : _storage = storage ?? const FlutterSecureStorage(),
      _key = userId == null ? keyPrefix : '$keyPrefix.$userId';

  final FlutterSecureStorage _storage;

  /// Prefix of the key under which each account's JSON array of cars is
  /// stored.
  static const String keyPrefix = 'sarthi.ride.savedCars';

  final String _key;

  @override
  Future<List<Car>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Car.fromJson)
          .whereType<Car>()
          .toList(growable: false);
    } catch (_) {
      // Corrupt / outdated payload — drop it rather than fail every lookup.
      await _storage.delete(key: _key);
      return const [];
    }
  }

  @override
  Future<void> write(List<Car> cars) => _storage.write(
    key: _key,
    value: jsonEncode(cars.map((c) => c.toJson()).toList()),
  );
}
