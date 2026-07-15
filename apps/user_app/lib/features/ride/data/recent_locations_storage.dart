import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/pickup_location.dart';

/// Durable persistence for the customer's recently used pickups.
///
/// An interface so tests can swap in a fake without the platform channel that
/// `flutter_secure_storage` needs. Ordered most-recent-first, matching how the
/// repository writes it.
abstract interface class RecentLocationsStorage {
  /// Reads the saved pickups, or an empty list if none / unreadable.
  Future<List<PickupLocation>> read();

  /// Persists [locations], replacing any previous list.
  Future<void> write(List<PickupLocation> locations);
}

/// [RecentLocationsStorage] backed by the OS keychain / keystore via
/// `flutter_secure_storage` — pickup history is mildly sensitive, so it rides
/// the same secure store as the auth session rather than plain preferences.
class SecureRecentLocationsStorage implements RecentLocationsStorage {
  SecureRecentLocationsStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Key under which the JSON array of pickups is stored.
  static const String _key = 'sarthi.ride.recentPickups';

  @override
  Future<List<PickupLocation>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PickupLocation.fromJson)
          .toList(growable: false);
    } catch (_) {
      // Corrupt / outdated payload — drop it rather than fail every lookup.
      await _storage.delete(key: _key);
      return const [];
    }
  }

  @override
  Future<void> write(List<PickupLocation> locations) => _storage.write(
    key: _key,
    value: jsonEncode(locations.map((l) => l.toJson()).toList()),
  );
}
