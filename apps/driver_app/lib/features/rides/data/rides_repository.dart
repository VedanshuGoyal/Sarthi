import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/ride.dart';

/// Raised when a ride request fails. [message] is safe to show the driver.
class RidesException implements Exception {
  const RidesException(this.message, {this.code});

  final String message;

  /// The backend's machine-readable tag — `ride_unavailable` (someone else
  /// took it, or the customer cancelled it), `ride_clash`,
  /// `transmission_mismatch`, `ride_state` (also: not completed, or
  /// already rated), `ride_in_progress`, `start_otp_incorrect`,
  /// `start_otp_reset`, `kyc_not_cleared`, `invalid_rating` — or null for
  /// generic failures.
  final String? code;

  @override
  String toString() => 'RidesException($code): $message';
}

/// The single entry point for the driver's ride data — view models talk only
/// to this, never to an HTTP client.
///
/// Fronts the backend's `/driver/rides`, `/driver/earnings` and
/// `/driver/duty` endpoints. Every route is scoped server-side to the
/// session's driver, so nothing here sends a driver id.
class RidesRepository {
  RidesRepository({http.Client? client, String? baseUrl, this._tokenGetter})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token from in-memory session state.
  final String? Function()? _tokenGetter;

  /// Open rides the driver can take, soonest first. Passing the driver's
  /// position limits them to nearby pickups and adds each one's distance.
  Future<List<Ride>> requests({double? lat, double? lng}) async {
    final query = lat != null && lng != null ? '?lat=$lat&lng=$lng' : '';
    return _rides(await _send('GET', '/driver/rides/requests$query'));
  }

  /// Every ride assigned to the driver, latest scheduled first.
  Future<List<Ride>> myRides() async =>
      _rides(await _send('GET', '/driver/rides'));

  /// Applies [action] to ride [id]. Returns the updated ride, or null for
  /// actions that give the ride up ([RideAction.decline],
  /// [RideAction.release]). [RideAction.start] needs [otp], the code the
  /// customer reads out from their app. [RideAction.rate] needs [stars]
  /// (1–5) and takes an optional [note].
  Future<Ride?> act(
    String id,
    RideAction action, {
    String? otp,
    int? stars,
    String? note,
  }) async {
    final body = await _send(
      'POST',
      '/driver/rides/$id/${action.wireName}',
      payload: switch (action) {
        RideAction.start => {'otp': otp ?? ''},
        RideAction.rate => {
          'stars': stars ?? 0,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        _ => null,
      },
    );
    if (body.isEmpty) return null;
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? Ride.tryParse(decoded['ride'])
        : null;
  }

  /// The driver's earnings summary.
  Future<Earnings> earnings() async {
    final body = await _send('GET', '/driver/earnings');
    return Earnings.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Tells the backend the driver is online (optionally where) or offline.
  Future<void> setDuty({required bool online, double? lat, double? lng}) =>
      _send(
        'PUT',
        '/driver/duty',
        payload: {
          'online': online,
          if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
        },
      );

  /// Shares the driver's live position while a ride is in its tracking
  /// window (see [Ride.isTrackableAt]). This alone never puts the driver
  /// online — that's [setDuty].
  Future<void> shareLocation({
    required double lat,
    required double lng,
    double? heading,
  }) => _send(
    'PUT',
    '/driver/location',
    payload: {
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
    },
  );

  static List<Ride> _rides(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map<String, dynamic> ? decoded['rides'] : null;
    return [
      for (final item in list as List<dynamic>? ?? const [])
        ?Ride.tryParse(item),
    ];
  }

  Future<String> _send(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    final token = _tokenGetter?.call();
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (payload != null) request.body = jsonEncode(payload);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } catch (_) {
      throw const RidesException(
        "Can't reach the server. Check your connection and try again.",
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Not JSON — fall back to the generic message.
    }
    final message = switch (body['error']) {
      final String m when m.isNotEmpty => _sentence(m),
      _ => 'Something went wrong. Please try again.',
    };
    throw RidesException(message, code: body['code'] as String?);
  }

  /// The backend's errors are lower-case fragments; show them as sentences.
  static String _sentence(String m) =>
      '${m[0].toUpperCase()}${m.substring(1)}${m.endsWith('.') ? '' : '.'}';
}
