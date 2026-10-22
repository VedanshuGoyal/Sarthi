import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/google_maps_config.dart';
import '../../../core/config/ola_maps_config.dart';
import '../domain/geo_point.dart';
import '../domain/pickup_location.dart';
import '../domain/place_suggestion.dart';
import '../domain/service_area.dart';
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

/// Supplies a valid Ola Maps OAuth bearer token. Production fetches it from the
/// Sarthi backend ([OlaMapsAuthenticator]); tests inject a canned token.
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
    String? routesBaseUrl,
    String? routesApiKey,
    this._maxRecents = 7,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? OlaMapsAuthenticator().accessToken,
       _baseUrl = baseUrl ?? OlaMapsConfig.baseUrl,
       _positionFetcher = positionFetcher ?? _devicePosition,
       _recentsApi = recentsApi ?? RecentPickupsApi(),
       _recentsCache = recentsCache ?? SecureRecentLocationsStorage(),
       _routesBaseUrl = routesBaseUrl ?? GoogleMapsConfig.routesBaseUrl,
       _routesApiKey = routesApiKey ?? GoogleMapsConfig.apiKey;

  final http.Client _client;
  final AccessTokenProvider _tokenProvider;
  final String _baseUrl;
  final PositionFetcher _positionFetcher;

  /// Google Routes API endpoint + key for drive-time estimates (the rest of the
  /// repository talks to Ola Maps).
  final String _routesBaseUrl;
  final String _routesApiKey;

  /// Backend is the source of truth for recents; [_recentsCache] mirrors it for
  /// offline reads.
  final RecentPickupsApi _recentsApi;
  final RecentLocationsStorage _recentsCache;
  final int _maxRecents;

  /// Shortest query worth sending to autocomplete; below this we show nothing.
  static const int minQueryLength = 4;

  /// Suggests places matching [input]. [near] biases results toward the user's
  /// area; absent, results are biased to the service-area centre so nearby
  /// Delhi-NCR places rank first. Returns an empty list for too-short queries.
  ///
  /// Predictions we can already tell sit outside the [ServiceArea] are dropped
  /// here; ones without coordinates pass through and are re-checked when the
  /// customer selects them.
  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    GeoPoint? near,
  }) async {
    final query = input.trim();
    if (query.length < minQueryLength) return const [];

    final json = await _getJson('/places/v1/autocomplete', {
      'input': query,
      'location': (near ?? ServiceArea.center).toLatLngParam(),
    });

    final predictions = json['predictions'];
    if (predictions is! List) return const [];
    return predictions
        .whereType<Map<String, dynamic>>()
        .map(PlaceSuggestion.fromOlaPrediction)
        .where((s) => s.placeId.isNotEmpty)
        .where((s) => s.point == null || ServiceArea.contains(s.point!))
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
    return PickupLocation(address: point.toLatLngParam(), point: point);
  }

  /// The driving time from [start] to [destination].
  ///
  /// With no [departureAt] the trip is treated as leaving about now and the
  /// estimate comes from the Ola Maps Directions API — cheap, priced into the
  /// existing Ola plan, based on current traffic. With a [departureAt] the
  /// costlier Google Routes API predicts traffic for that departure; callers
  /// should only pass one for departures too far out for current traffic to be
  /// a good proxy (see `scheduling.isNearTermDeparture`). Throws a
  /// [LocationException] when no route with a duration comes back.
  Future<Duration> travelTime({
    required GeoPoint start,
    required GeoPoint destination,
    DateTime? departureAt,
  }) => departureAt == null
      ? _olaTravelTime(start, destination)
      : _googleTravelTime(start, destination, departureAt);

  /// Current-traffic drive time via Ola Maps Directions. Sums the legs of the
  /// first returned route.
  Future<Duration> _olaTravelTime(GeoPoint start, GeoPoint destination) async {
    // Ola's directions endpoint is a POST that carries its input in the query
    // string; the body stays empty. The full endpoint, not `/basic`: only it
    // models real driving speeds (`/basic` returns ~10 km/h averages, wildly
    // overestimating drive times).
    final json = await _requestJson('POST', '/routing/v1/directions', {
      'origin': start.toLatLngParam(),
      'destination': destination.toLatLngParam(),
    });

    final routes = json['routes'];
    if (routes is List) {
      for (final route in routes.whereType<Map<String, dynamic>>()) {
        final legs = route['legs'];
        if (legs is! List) continue;
        var seconds = 0;
        var found = false;
        for (final leg in legs.whereType<Map<String, dynamic>>()) {
          final duration = leg['duration'];
          if (duration is num) {
            seconds += duration.toInt();
            found = true;
          }
        }
        if (found) return Duration(seconds: seconds);
      }
    }
    throw const LocationException('Unexpected response from the maps service.');
  }

  /// Traffic-aware drive time for a future departure, via the Google Routes
  /// API (`computeRoutes`). The departure is only sent when it still lies in
  /// the future, since Google rejects past departure times.
  Future<Duration> _googleTravelTime(
    GeoPoint start,
    GeoPoint destination,
    DateTime departureAt,
  ) async {
    if (_routesApiKey.isEmpty) {
      throw const LocationException(
        'Drive-time estimates are not set up on this build.',
      );
    }

    final departure = departureAt.toUtc();
    final json = await _postGoogleJson('/directions/v2:computeRoutes', {
      'origin': _routesWaypoint(start),
      'destination': _routesWaypoint(destination),
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_AWARE',
      if (departure.isAfter(DateTime.now().toUtc()))
        'departureTime': departure.toIso8601String(),
    });

    final routes = json['routes'];
    if (routes is List) {
      for (final route in routes.whereType<Map<String, dynamic>>()) {
        final seconds = _parseGoogleDuration(route['duration']);
        if (seconds != null) return Duration(seconds: seconds);
      }
    }
    throw const LocationException('Unexpected response from the maps service.');
  }

  /// A Routes API waypoint literal for [point].
  static Map<String, dynamic> _routesWaypoint(GeoPoint point) => {
    'location': {
      'latLng': {'latitude': point.latitude, 'longitude': point.longitude},
    },
  };

  /// Routes API durations arrive as protobuf-style strings ("5100s"); null
  /// when [value] isn't one.
  static int? _parseGoogleDuration(Object? value) {
    if (value is! String || !value.endsWith('s')) return null;
    return int.tryParse(value.substring(0, value.length - 1));
  }

  /// POSTs [body] to the Google Routes API at [path], authorized with the API
  /// key, asking only for route durations. Same failure mapping as the Ola
  /// requests so callers see one exception type.
  Future<Map<String, dynamic>> _postGoogleJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_routesBaseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _routesApiKey,
          'X-Goog-FieldMask': 'routes.duration',
        },
        body: jsonEncode(body),
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

  /// Reads the device's current position and reverse-geocodes it into a
  /// confirmable pickup. Throws a [LocationPermissionException] /
  /// [LocationServiceDisabledException] when GPS is unavailable.
  Future<PickupLocation> currentLocation() async {
    final point = await _positionFetcher();
    return reverseGeocode(point);
  }

  /// The device's raw coordinates, with no reverse-geocode round-trip — used to
  /// centre the map picker on the user before they start panning. Throws a
  /// [LocationPermissionException] / [LocationServiceDisabledException] when GPS
  /// is unavailable, so callers can fall back to a default view.
  Future<GeoPoint> currentPoint() => _positionFetcher();

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
  /// returns the decoded JSON object.
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> params,
  ) => _requestJson('GET', path, params);

  /// Sends [method] to [path] with [params] in the query string, authorized
  /// with a fresh OAuth bearer token, and returns the decoded JSON object.
  /// Centralises the "no creds / no network / bad status" failure modes.
  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path,
    Map<String, String> params,
  ) async {
    // Throws LocationException when maps aren't set up on the backend or the
    // token request fails — surfaced to the caller unchanged.
    final token = await _tokenProvider();

    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final headers = {'Authorization': 'Bearer $token'};

    final http.Response response;
    try {
      response = method == 'POST'
          ? await _client.post(uri, headers: headers)
          : await _client.get(uri, headers: headers);
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
    return GeoPoint(latitude: position.latitude, longitude: position.longitude);
  }
}
