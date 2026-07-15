import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/geo_point.dart';
import '../domain/pickup_location.dart';

/// Raised when the recent-pickups backend is unreachable or returns an error.
/// [LocationRepository] catches this and falls back to the on-device cache.
class RecentPickupsApiException implements Exception {
  const RecentPickupsApiException(this.message);
  final String message;
  @override
  String toString() => 'RecentPickupsApiException: $message';
}

/// Talks to the Sarthi backend's per-user pickup history
/// (`GET`/`POST /me/recent-pickups`).
///
/// The backend (PostgreSQL) is the source of truth for recents; it owns
/// de-duplication and capping. [LocationRepository] mirrors each response into
/// on-device storage so the list still shows when offline.
class RecentPickupsApi {
  RecentPickupsApi({
    http.Client? client,
    String? baseUrl,
    String? Function()? tokenGetter,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _tokenGetter = tokenGetter ?? _noToken;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token from in-memory auth state. Returns null when
  /// unauthenticated (the backend then rejects the request).
  final String? Function() _tokenGetter;

  static const String _path = '/me/recent-pickups';

  /// Default token getter when none is injected — always unauthenticated.
  static String? _noToken() => null;

  /// The user's recent pickups, newest first.
  Future<List<PickupLocation>> list() async {
    final response = await _send(() => _client.get(_uri(), headers: _headers()));
    return _parse(response);
  }

  /// Records [pickup] as the newest recent and returns the updated list.
  Future<List<PickupLocation>> remember(PickupLocation pickup) async {
    final body = jsonEncode({
      'placeId': pickup.placeId ?? '',
      'address': pickup.address,
      'lat': pickup.point.latitude,
      'lng': pickup.point.longitude,
    });
    final response = await _send(
      () => _client.post(_uri(), headers: _headers(json: true), body: body),
    );
    return _parse(response);
  }

  Uri _uri() => Uri.parse('$_baseUrl$_path');

  Map<String, String> _headers({bool json = false}) {
    final token = _tokenGetter();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _send(
    Future<http.Response> Function() run,
  ) async {
    final http.Response response;
    try {
      response = await run();
    } catch (_) {
      throw const RecentPickupsApiException("Can't reach the server.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RecentPickupsApiException(
        'Recent-pickups request failed (${response.statusCode}).',
      );
    }
    return response;
  }

  List<PickupLocation> _parse(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final recents = decoded['recents'];
    if (recents is! List) return const [];
    return recents
        .whereType<Map<String, dynamic>>()
        .map(_pickupFrom)
        .toList(growable: false);
  }

  PickupLocation _pickupFrom(Map<String, dynamic> json) {
    final placeId = json['placeId'] as String?;
    return PickupLocation(
      address: json['address'] as String? ?? '',
      point: GeoPoint(
        latitude: (json['lat'] as num?)?.toDouble() ?? 0,
        longitude: (json['lng'] as num?)?.toDouble() ?? 0,
      ),
      placeId: (placeId == null || placeId.isEmpty) ? null : placeId,
    );
  }
}
