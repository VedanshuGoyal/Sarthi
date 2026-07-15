import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/ola_maps_config.dart';
import '../domain/geo_point.dart';
import '../domain/pickup_location.dart';
import '../domain/place_suggestion.dart';
import 'ola_maps_authenticator.dart';
import 'recent_locations_storage.dart';
import 'recent_pickups_api.dart';

/// Raised when a location lookup fails. [message] is safe to show to the user.
class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => 'LocationException: $message';
}

/// Raised when the app can't read GPS because permission was refused. Distinct
/// type so the view model can steer the user toward searching instead.
class LocationPermissionException extends LocationException {
  const LocationPermissionException(super.message);
}

/// Raised when device location services are switched off entirely.
class LocationServiceDisabledException extends LocationException {
  const LocationServiceDisabledException(super.message);
}

/// Reads the device's current coordinates. Injectable so tests and previews can
/// supply a fixed position without touching the GPS plugin.
typedef PositionFetcher = Future<GeoPoint> Function();

/// Supplies a valid Ola Maps OAuth bearer token. Injectable so tests can pass a
/// canned token and production can later swap client-side minting for a
/// backend-minted one without touching the repository.
typedef AccessTokenProvider = Future<String> Function();

/// The single interface for pickup-location data access.
///
/// View models talk only to this repository — never to the Ola HTTP endpoints
/// or the Geolocator plugin directly. It wraps both: Ola Maps Places for
/// search + reverse-geocoding, and the device GPS for "use my current
/// location", mapping every failure into a [LocationException] the UI can show.
class LocationRepository {
  LocationRepository({
    http.Client? client,
    AccessTokenProvider? tokenProvider,
    String? baseUrl,
    PositionFetcher? positionFetcher,
    RecentPickupsApi? recentsApi,
    RecentLocationsStorage? recentsCache,
    this._maxRecents = 7,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? OlaMapsAuthenticator().accessToken,
       _baseUrl = baseUrl ?? OlaMapsConfig.baseUrl,
       _positionFetcher = positionFetcher ?? _devicePosition,
       _recentsApi = recentsApi ?? RecentPickupsApi(),
       _recentsCache = recentsCache ?? SecureRecentLocationsStorage();

  final http.Client _client;
  final AccessTokenProvider _tokenProvider;
  final String _baseUrl;
  final PositionFetcher _positionFetcher;

  /// Backend is the source of truth for recents; [_recentsCache] mirrors it for
  /// offline reads.
  final RecentPickupsApi _recentsApi;
  final RecentLocationsStorage _recentsCache;
  final int _maxRecents;

  /// Shortest query worth sending to autocomplete; below this we show nothing.
  static const int minQueryLength = 4;

  /// Suggests places matching [input]. [near] biases results toward the user's
  /// area when known. Returns an empty list for too-short queries.
  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    GeoPoint? near,
  }) async {
    final query = input.trim();
    if (query.length < minQueryLength) return const [];

    final json = await _getJson('/places/v1/autocomplete', {
      'input': query,
      if (near != null) 'location': near.toLatLngParam(),
    });

    final predictions = json['predictions'];
    if (predictions is! List) return const [];
    return predictions
        .whereType<Map<String, dynamic>>()
        .map(PlaceSuggestion.fromOlaPrediction)
        .where((s) => s.placeId.isNotEmpty)
        .toList(growable: false);
  }

  /// Resolves [point] to a street address via Ola reverse-geocoding.
  Future<PickupLocation> reverseGeocode(GeoPoint point) async {
    final json = await _getJson('/places/v1/reverse-geocode', {
      'latlng': point.toLatLngParam(),
    });

    final results = json['results'];
    if (results is List) {
      for (final result in results.whereType<Map<String, dynamic>>()) {
        final address = result['formatted_address'] as String?;
        if (address != null && address.isNotEmpty) {
          return PickupLocation(
            address: address,
            point: point,
            placeId: result['place_id'] as String?,
          );
        }
      }
    }
    // No street match (e.g. a remote point): fall back to the raw coordinates
    // so the user still gets a confirmable pickup rather than a dead end.
    return PickupLocation(
      address: point.toLatLngParam(),
      point: point,
    );
  }

  /// Reads the device's current position and reverse-geocodes it into a
  /// confirmable pickup. Throws a [LocationPermissionException] /
  /// [LocationServiceDisabledException] when GPS is unavailable.
  Future<PickupLocation> currentLocation() async {
    final point = await _positionFetcher();
    return reverseGeocode(point);
  }

  /// The locally cached recents — instant, offline, no network. Callers paint
  /// this immediately, then call [recentPickups] to refresh from the backend.
  Future<List<PickupLocation>> cachedRecents() => _recentsCache.read();

  /// Refreshes recents from the backend (source of truth), most-recent-first,
  /// and updates the on-device cache; on any failure it serves the cached copy
  /// so recents still work offline. Either way, no Ola request is involved.
  Future<List<PickupLocation>> recentPickups() async {
    try {
      final list = await _recentsApi.list();
      await _recentsCache.write(list);
      return list;
    } catch (_) {
      return _recentsCache.read();
    }
  }

  /// Records [pickup] as the newest recent on the backend (which de-duplicates
  /// and caps), then mirrors the result into the cache. If the backend is
  /// unreachable it updates the cache locally so the pickup still shows next
  /// time, and the next successful sync reconciles with the server.
  Future<List<PickupLocation>> rememberPickup(PickupLocation pickup) async {
    try {
      final list = await _recentsApi.remember(pickup);
      await _recentsCache.write(list);
      return list;
    } catch (_) {
      return _rememberInCache(pickup);
    }
  }

  /// Offline fallback: apply the same newest-first / de-dupe / cap rules the
  /// backend would, directly to the cache.
  Future<List<PickupLocation>> _rememberInCache(PickupLocation pickup) async {
    final key = _recentKey(pickup);
    final existing = await _recentsCache.read();
    final updated = <PickupLocation>[
      pickup,
      ...existing.where((p) => _recentKey(p) != key),
    ];
    if (updated.length > _maxRecents) {
      updated.removeRange(_maxRecents, updated.length);
    }
    await _recentsCache.write(updated);
    return updated;
  }

  /// Identity for de-duplication: the Ola place id when present, else the
  /// normalised address, so the same place saved twice collapses to one entry.
  static String _recentKey(PickupLocation p) {
    final id = p.placeId;
    if (id != null && id.isNotEmpty) return 'id:$id';
    return 'addr:${p.address.trim().toLowerCase()}';
  }

  /// GETs [path] with [params], authorized with a fresh OAuth bearer token, and
  /// returns the decoded JSON object. Centralises the "no creds / no network /
  /// bad status" failure modes.
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> params,
  ) async {
    // Throws LocationException when credentials are missing or the token
    // request fails — surfaced to the caller unchanged.
    final token = await _tokenProvider();

    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: params.isEmpty ? null : params);

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw const LocationException(
        "Can't reach the maps service. Check your connection and try again.",
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocationException(
        'The maps service is unavailable right now. Please try again.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const LocationException('Unexpected response from the maps service.');
  }

  /// Default [PositionFetcher]: checks services + permission, then reads a
  /// single high-accuracy fix from the Geolocator plugin.
  static Future<GeoPoint> _devicePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabledException(
        'Location is turned off. Switch it on to use your current spot.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionException(
        'Location permission was declined. Search for your pickup instead.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Location is blocked. Enable it in Settings, or search instead.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
