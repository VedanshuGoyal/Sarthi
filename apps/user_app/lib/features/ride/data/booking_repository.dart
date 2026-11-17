import 'dart:convert';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/driver_location.dart';
import '../domain/multi_stop_trip.dart';
import '../domain/my_booking.dart';
import '../domain/one_way_trip.dart';
import '../domain/payment_checkout.dart';
import '../domain/round_trip_booking.dart';

/// Raised when the booking backend is unreachable or rejects the submission.
/// The caller decides how to surface it (the home screen notes it in the
/// confirmation snackbar).
///
/// [code] is the server's error tag when it gave one; a [paymentDue] refusal
/// also names the unpaid ride in [bookingId], so the caller can take the
/// customer to its Pay button.
class BookingSubmitException implements Exception {
  const BookingSubmitException(this.message, {this.code, this.bookingId});

  /// The server's `payment_due` refusal: the customer has a completed ride,
  /// [bookingId], still to pay for.
  const BookingSubmitException.paymentDue(String this.bookingId)
    : message = 'Pay for your last ride before booking another.',
      code = paymentDueCode;

  /// The error tag of a booking refused while a ride is unpaid.
  static const String paymentDueCode = 'payment_due';

  final String message;
  final String? code;
  final String? bookingId;

  /// Whether the booking was refused because a finished ride is unpaid.
  bool get isPaymentDue => code == paymentDueCode && bookingId != null;

  @override
  String toString() => 'BookingSubmitException: $message';
}

/// A fresh random UUID (version 4) from a secure source, sent as the
/// `Idempotency-Key` of one booking attempt so a retry can't book twice.
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) r.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// Why the server turned down an action on an existing booking — the `code`
/// tag of its error body, so callers can react without matching on text.
enum BookingErrorCode {
  /// Not this customer's booking, or no such id.
  notFound('booking_not_found'),

  /// The booking has moved on: started, finished, cancelled or rated.
  wrongState('booking_state'),

  /// Stars outside 1–5, or a note that's too long.
  invalidRating('invalid_rating'),

  /// The driver's location isn't shared for this ride (yet, or any more).
  notTracking('not_tracking'),

  /// The ride is already paid for.
  alreadyPaid('already_paid'),

  /// The server has no payment gateway set up.
  paymentsOff('payments_not_configured'),

  /// The server couldn't reach the payment gateway.
  paymentGateway('payment_gateway'),

  /// Cancelling now costs more than the customer agreed to — the driver
  /// reached the pickup after the confirmation opened. Nothing changed; the
  /// fee is in [BookingActionException.feePaise].
  cancellationFee('cancellation_fee'),

  /// The trip can't be ended early: it isn't in progress.
  cannotEnd('cannot_end'),

  /// The server was unreachable, or sent a tag this app version doesn't know.
  other('');

  const BookingErrorCode(this.wireName);

  final String wireName;

  static BookingErrorCode fromWire(Object? value) => values.firstWhere(
    (c) => c != other && c.wireName == value,
    orElse: () => other,
  );
}

/// Raised when cancelling, rating or tracking a booking fails. [message] is
/// safe to show; [code] says why, for the caller to pick its own wording.
class BookingActionException implements Exception {
  const BookingActionException(
    this.message, {
    this.code = BookingErrorCode.other,
    this.statusCode,
    this.feePaise,
  });

  final String message;
  final BookingErrorCode code;

  /// The HTTP status, or null when the server couldn't be reached.
  final int? statusCode;

  /// What cancelling now costs, on a [BookingErrorCode.cancellationFee]
  /// refusal; null when the server didn't say.
  final int? feePaise;

  @override
  String toString() =>
      'BookingActionException(${code.wireName}, $statusCode): $message';
}

/// Sends confirmed bookings to the Sarthi backend (`POST /me/bookings`),
/// reads them back with their status, driver and start code
/// (`GET /me/bookings`), and acts on one: cancel it, end it early, rate the
/// driver, follow the driver on the map, or pay for it
/// (`/me/bookings/{id}/…`).
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

  /// Each submit sends [idempotencyKey] (a fresh one when null): pass the
  /// same key when retrying the same booking, so a submit that landed but
  /// whose reply was lost isn't booked twice. Throws
  /// [BookingSubmitException] — [BookingSubmitException.isPaymentDue] while
  /// a finished ride is still unpaid, from servers before unpaid rides were
  /// added to the next payment instead.
  Future<void> submitRoundTrip(
    RoundTripBooking booking, {
    String? idempotencyKey,
  }) => _submit('roundTrip', booking.toJson(), idempotencyKey);

  Future<void> submitOneWay(OneWayTrip trip, {String? idempotencyKey}) =>
      _submit('oneWay', trip.toJson(), idempotencyKey);

  Future<void> submitMultiStop(MultiStopTrip trip, {String? idempotencyKey}) =>
      _submit('multiStop', trip.toJson(), idempotencyKey);

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
    // Not a list of bookings (a proxy's page, say): a load failure the
    // Activity tab can show, not a raw parse error.
    final decoded = _decode(response.body);
    final list = decoded?['bookings'];
    if (decoded == null || list is! List<dynamic>?) {
      throw const BookingSubmitException(
        'The server sent an unexpected reply.',
      );
    }
    return [for (final item in list ?? const []) ?MyBooking.tryParse(item)];
  }

  /// Cancels a ride that hasn't started (`POST /me/bookings/{id}/cancel`),
  /// with the customer's [reason] if they gave one, and returns it as now
  /// stored — with its fee due when the driver was at the pickup.
  ///
  /// [acceptFeePaise] is the fee the customer was shown and agreed to (0
  /// when cancelling was free); it's always sent, and the server never
  /// charges more. Throws [BookingActionException] — `cancellationFee` (with
  /// [BookingActionException.feePaise]) when cancelling now costs more,
  /// `wrongState` once the trip has started, finished or was already
  /// cancelled.
  Future<MyBooking> cancel(
    String id, {
    String? reason,
    int acceptFeePaise = 0,
  }) async {
    final reply = await _act(
      'POST',
      id,
      'cancel',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'acceptFeePaise': acceptFeePaise,
      },
    );
    return _bookingIn(reply);
  }

  /// Ends a trip in progress now (`POST /me/bookings/{id}/end`) and returns
  /// it completed: `farePaise` is then the charge for the time used,
  /// `bookedFarePaise` the fare as booked, and it's due for payment. Throws
  /// [BookingActionException] — `cannotEnd` when the trip isn't in progress.
  Future<MyBooking> endTrip(String id) async {
    final reply = await _act('POST', id, 'end');
    return _bookingIn(reply);
  }

  /// Rates the driver of a completed ride, 1–5 [stars] and an optional
  /// [note] (`POST /me/bookings/{id}/rating`), and returns the ride with
  /// `myRating` set. Throws [BookingActionException] — `wrongState` when the
  /// ride isn't completed or was already rated, `invalidRating` for bad input.
  Future<MyBooking> rate(String id, int stars, {String? note}) async {
    final reply = await _act(
      'POST',
      id,
      'rating',
      body: {
        'stars': stars,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return _bookingIn(reply);
  }

  /// The assigned driver's latest fix (`GET /me/bookings/{id}/driver-location`),
  /// or null when they haven't shared one in the last 30 minutes. Throws
  /// [BookingActionException] — `notTracking` outside the tracking window.
  Future<DriverLocation?> driverLocation(String id) async {
    final reply = await _act('GET', id, 'driver-location');
    return DriverLocation.tryParse(reply['location']);
  }

  /// The photo of the driver on booking [id]
  /// (`GET /me/bookings/{id}/driver-photo`), for an [Image] to load.
  /// [version] is the booking's `driverPhotoVersion`; it's in the URL, so
  /// the image cache keeps one download per photo across list refreshes.
  ImageProvider driverPhoto(String id, String version) {
    final uri = Uri.parse(
      '$_baseUrl$_path/${Uri.encodeComponent(id)}/driver-photo',
    ).replace(queryParameters: {'v': version});
    final token = _tokenGetter();
    return NetworkImage(
      uri.toString(),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
  }

  /// Opens a UPI checkout for a completed ride, or a cancelled one whose fee
  /// is due (`POST /me/bookings/{id}/payment`), for the payment SDK to show;
  /// the server sets the amount. Throws [BookingActionException] —
  /// `alreadyPaid` when it's paid for, `wrongState` before it's completed,
  /// `paymentsOff` / `paymentGateway` when payments can't be taken.
  Future<PaymentCheckout> startPayment(String id) async {
    final reply = await _act('POST', id, 'payment');
    return PaymentCheckout.tryParse(reply['checkout']) ??
        (throw const BookingActionException(
          'The server sent an unexpected reply.',
        ));
  }

  /// Asks the server to re-check the ride's payment with the gateway, after
  /// the payment page closes (`POST /me/bookings/{id}/payment/sync`), and
  /// returns the ride as it now stands.
  Future<MyBooking> syncPayment(String id) async {
    final reply = await _act('POST', id, 'payment/sync');
    return _bookingIn(reply);
  }

  /// Sends one action on booking [id] and returns the decoded reply, turning
  /// any failure into a [BookingActionException] carrying the server's code.
  Future<Map<String, dynamic>> _act(
    String method,
    String id,
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$_path/${Uri.encodeComponent(id)}/$action');
    final http.Response response;
    try {
      response = method == 'GET'
          ? await _client.get(uri, headers: _headers())
          : await _client.post(
              uri,
              headers: _headers(),
              body: jsonEncode(body ?? const {}),
            );
    } catch (_) {
      throw const BookingActionException("Can't reach the server.");
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The server's error is a lower-case sentence; show it as one.
      final error = decoded?['error'];
      final fee = decoded?['feePaise'];
      throw BookingActionException(
        error is String && error.isNotEmpty
            ? _sentence(error)
            : 'Something went wrong (${response.statusCode}).',
        code: BookingErrorCode.fromWire(decoded?['code']),
        statusCode: response.statusCode,
        feePaise: fee is num && fee > 0 ? fee.toInt() : null,
      );
    }
    return decoded ?? const {};
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// The `booking` of a cancel/end/rate/sync reply.
  static MyBooking _bookingIn(Map<String, dynamic> reply) =>
      MyBooking.tryParse(reply['booking']) ??
      (throw const BookingActionException(
        'The server sent an unexpected reply.',
      ));

  /// The header naming one booking attempt; the server answers a repeat of
  /// it (200, `duplicate`) with the booking it already made.
  static const String idempotencyHeader = 'Idempotency-Key';

  Future<void> _submit(
    String tripType,
    Map<String, dynamic> details,
    String? idempotencyKey,
  ) async {
    final body = jsonEncode({'tripType': tripType, 'details': details});
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl$_path'),
        headers: {
          ..._headers(),
          idempotencyHeader: idempotencyKey ?? newIdempotencyKey(),
        },
        body: body,
      );
    } catch (_) {
      throw const BookingSubmitException("Can't reach the server.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decode(response.body);
      final code = decoded?['code'];
      final unpaid = decoded?['bookingId'];
      if (code == BookingSubmitException.paymentDueCode &&
          unpaid is String &&
          unpaid.isNotEmpty) {
        throw BookingSubmitException.paymentDue(unpaid);
      }
      // The server says what was wrong ("pick a start time at least 45
      // minutes from now"); that's what the customer needs to fix it.
      final error = decoded?['error'];
      throw BookingSubmitException(
        error is String && error.isNotEmpty
            ? _sentence(error)
            : 'Booking request failed (${response.statusCode}).',
        code: code is String && code.isNotEmpty ? code : null,
      );
    }
  }

  /// The server's lower-case error fragment as a sentence.
  static String _sentence(String error) =>
      '${error[0].toUpperCase()}${error.substring(1)}'
      '${error.endsWith('.') ? '' : '.'}';

  Map<String, String> _headers() {
    final token = _tokenGetter();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
