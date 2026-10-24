import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/multi_stop_trip.dart';
import '../domain/my_booking.dart';
import '../domain/one_way_trip.dart';
import '../domain/round_trip_booking.dart';

/// Raised when the booking backend is unreachable or rejects the submission.
/// The caller decides how to surface it (the home screen notes it in the
/// confirmation snackbar).
class BookingSubmitException implements Exception {
  const BookingSubmitException(this.message);
  final String message;
  @override
  String toString() => 'BookingSubmitException: $message';
}

/// Sends confirmed bookings to the Sarthi backend (`POST /me/bookings`) and
/// reads them back with their status, driver and start code
/// (`GET /me/bookings`).
///
/// The sole data-access seam for bookings, per the repository guideline.
class BookingRepository {
  BookingRepository({
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

  static const String _path = '/me/bookings';

  /// Default token getter when none is injected — always unauthenticated.
  static String? _noToken() => null;

  Future<void> submitRoundTrip(RoundTripBooking booking) =>
      _submit('roundTrip', booking.toJson());

  Future<void> submitOneWay(OneWayTrip trip) =>
      _submit('oneWay', trip.toJson());

  Future<void> submitMultiStop(MultiStopTrip trip) =>
      _submit('multiStop', trip.toJson());

  /// The customer's bookings, latest scheduled first, with their status,
  /// assigned driver and start code (`GET /me/bookings`). Throws
  /// [BookingSubmitException] when the server can't be reached or refuses.
  Future<List<MyBooking>> myBookings() async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$_baseUrl$_path'),
        headers: _headers(),
      );
    } catch (_) {
      throw const BookingSubmitException("Can't reach the server.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BookingSubmitException(
        'Loading your rides failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic> ? decoded['bookings'] : null;
    return [
      for (final item in list as List<dynamic>? ?? const [])
        ?MyBooking.tryParse(item),
    ];
  }

  Future<void> _submit(String tripType, Map<String, dynamic> details) async {
    final body = jsonEncode({'tripType': tripType, 'details': details});
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl$_path'),
        headers: _headers(),
        body: body,
      );
    } catch (_) {
      throw const BookingSubmitException("Can't reach the server.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BookingSubmitException(
        'Booking request failed (${response.statusCode}).',
      );
    }
  }

  Map<String, String> _headers() {
    final token = _tokenGetter();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
