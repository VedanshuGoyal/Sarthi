import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/multi_stop_trip.dart';
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

/// Sends confirmed bookings to the Sarthi backend (`POST /me/bookings`).
///
/// The sole data-access seam for booking submission, per the repository
/// guideline. The server currently just acknowledges the booking and records
/// its details; matchmaking and persistence come later, behind the same call.
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
