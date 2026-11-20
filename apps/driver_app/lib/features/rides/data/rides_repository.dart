import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../l10n/l10n.dart';
import '../domain/payout.dart';
import '../domain/ride.dart';

/// Raised when a ride request fails. [message] is safe to show the driver:
/// the backend's own words, or — when it gave none or couldn't be reached —
/// the app's, in the app's language.
class RidesException implements Exception {
  const RidesException(this.message, {this.code, this.statusCode});

  final String message;

  /// The HTTP status, or null when the server couldn't be reached.
  final int? statusCode;

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
/// Fronts the backend's `/driver/rides`, `/driver/earnings`,
/// `/driver/payouts` and `/driver/duty` endpoints. Every route is scoped
/// server-side to the session's driver, so nothing here sends a driver id.
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
    return _parse(body, (decoded) {
      return decoded is Map<String, dynamic>
          ? Ride.tryParse(decoded['ride'])
          : null;
    });
  }

  /// The driver's earnings summary.
  Future<Earnings> earnings() async {
    final body = await _send('GET', '/driver/earnings');
    return _parse(
      body,
      (decoded) => Earnings.fromJson(decoded as Map<String, dynamic>),
    );
  }

  /// The bank transfers MOJUD has recorded to the driver, newest first. An
  /// older server without the list answers 404, read as "none yet".
  Future<List<Payout>> payouts() async {
    final String body;
    try {
      body = await _send('GET', '/driver/payouts');
    } on RidesException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
    return _parse(body, (decoded) {
      final list = decoded is Map<String, dynamic> ? decoded['payouts'] : null;
      return [
        for (final item in list as List<dynamic>? ?? const [])
          ?Payout.tryParse(item),
      ];
    });
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
    payload: {'lat': lat, 'lng': lng, if (heading != null) 'heading': heading},
  );

  static List<Ride> _rides(String body) => _parse(body, (decoded) {
    final list = decoded is Map<String, dynamic> ? decoded['rides'] : null;
    return [
      for (final item in list as List<dynamic>? ?? const [])
        ?Ride.tryParse(item),
    ];
  });

  /// Decodes a 2xx [body] with [read]. A body that isn't the expected shape
  /// (a proxy's HTML page, say) is a [RidesException] like any other
  /// failure — a raw parse error would skip every view model's error
  /// handling, so the driver would see nothing happen.
  static T _parse<T>(String body, T Function(Object? decoded) read) {
    try {
      return read(jsonDecode(body));
    } catch (_) {
      throw RidesException(L10n.current.errorUnexpectedReply);
    }
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
      throw RidesException(L10n.current.errorNoConnection);
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
      _ => L10n.current.errorGeneric,
    };
    final code = body['code'];
    throw RidesException(
      message,
      code: code is String ? code : null,
      statusCode: response.statusCode,
    );
  }

  /// The backend's errors are lower-case fragments; show them as sentences.
  static String _sentence(String m) =>
      '${m[0].toUpperCase()}${m.substring(1)}${m.endsWith('.') ? '' : '.'}';
}
