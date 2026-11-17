import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';

/// One `CustomerBooking` as the backend sends it, with every field of the
/// contract filled in unless switched off.
Map<String, dynamic> bookingJson({
  String id = 'b1',
  String status = 'accepted',
  String tripType = 'multiStop',
  // Far ahead, so an open request isn't read as expired whenever tests run.
  String scheduledAt = '2030-10-26T05:00:00Z',
  bool withDriver = true,
  int ratingCount = 12,
  String? otp,
  Map<String, dynamic>? myRating,
  String? startedAt,
  String? completedAt,
  String? cancelReason,
  String cancelledBy = 'customer',
  String? paymentStatus,
  Map<String, dynamic>? payment,
  Map<String, dynamic>? fareBreakdown,
  int farePaise = 64000,
  int? cancellationFeePaise,
  int? bookedFarePaise,
  int? carriedPaise,
  int? hours,
  String endsAt = '2030-10-26T07:30:00Z',
}) => {
  'id': id,
  'tripType': tripType,
  'status': status,
  'scheduledAt': scheduledAt,
  'endsAt': endsAt,
  'hours': ?hours,
  'farePaise': farePaise,
  'fareEstimated': true,
  'pickup': {
    'address': 'Connaught Place, New Delhi',
    'lat': 28.6315,
    'lng': 77.2167,
  },
  'destination': {'address': 'Hauz Khas Village', 'lat': 0, 'lng': 0},
  'stopCount': 2,
  'stops': [
    {
      'place': {'address': 'Apollo Pharmacy', 'lat': 28.5677, 'lng': 77.2433},
      'task': 'Collect the prescription',
      'departBy': '2030-10-26T06:00:00Z',
    },
    {
      'place': {'address': 'Passport Seva Kendra', 'lat': 28.56, 'lng': 77.18},
      'task': 'Drop the forms',
      'departBy': '2030-10-26T07:00:00Z',
    },
  ],
  'estimatedMinutes': 150,
  'car': {
    'registration': 'DL01AB1234',
    'carType': 'sedan',
    'transmission': 'manual',
  },
  if (withDriver)
    'driver': {
      'name': 'Ravi Kumar',
      'phoneE164': '+919800000001',
      if (ratingCount > 0) 'rating': 4.7,
      'ratingCount': ratingCount,
    },
  'startOtp': ?otp,
  'createdAt': '2030-10-25T04:35:00Z',
  if (withDriver) 'acceptedAt': '2030-10-25T05:00:00Z',
  'startedAt': ?startedAt,
  'completedAt': ?completedAt,
  if (status == 'cancelled') ...{
    'cancelledAt': '2030-10-25T06:00:00Z',
    'cancelledBy': cancelledBy,
    'cancelReason': ?cancelReason,
  },
  'myRating': ?myRating,
  'paymentStatus': ?paymentStatus,
  'payment': ?payment,
  'fareBreakdown': ?fareBreakdown,
  'cancellationFeePaise': ?cancellationFeePaise,
  'bookedFarePaise': ?bookedFarePaise,
  'carriedPaise': ?carriedPaise,
};

/// An in-memory stand-in for the booking endpoints, so repository, view
/// model and screen tests run the real request/parse code with no network.
///
/// [bookings] is what `GET /me/bookings` lists; cancel, end and rating
/// rewrite the stored booking like the server does — a cancel at the pickup
/// costs the booking's `cancellationFeePaise`, refused (409
/// `cancellation_fee`) when the app agreed to less, and ending a trip early
/// charges [endedFarePaise]. A checkout is for the booking's own amount plus
/// its `carriedPaise`, and once a booking that carried dues is paid, every
/// other due booking is paid too and nothing is carried any more — the
/// server's carried-dues rule. [location] is the driver fix
/// to answer with (null → `{"location": null}`), and [locationError] a
/// `(status, code)` to fail the location call with instead.
class FakeBookingServer {
  FakeBookingServer(this.bookings);

  final List<Map<String, dynamic>> bookings;
  Map<String, dynamic>? location;
  (int, String)? locationError;

  /// A `(status, code)` the next cancel or rating fails with.
  (int, String)? actionError;

  /// A `(status, code)` opening a checkout fails with.
  (int, String)? paymentError;

  /// What ending a trip early charges, in paise.
  int endedFarePaise = 24000;

  /// How many payment re-checks it takes for the gateway to report the ride
  /// paid; null never does.
  int? paidAfterSyncs;
  int _syncs = 0;

  /// Every request, in order.
  final List<http.Request> requests = [];

  int get locationRequests =>
      requests.where((r) => r.url.path.endsWith('/driver-location')).length;

  BookingRepository repository() => BookingRepository(
    baseUrl: 'http://api',
    tokenGetter: () => 'tok',
    client: MockClient(_handle),
  );

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  static http.Response _error((int, String) error) =>
      _json({'error': 'refused by test', 'code': error.$2}, error.$1);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.pathSegments;
    if (request.url.path == '/me/bookings') {
      return _json({'bookings': bookings});
    }
    final index = bookings.indexWhere((b) => b['id'] == path[2]);
    if (index < 0) return _error((404, 'booking_not_found'));
    switch (path[3]) {
      case 'cancel':
        if (actionError case final error?) return _error(error);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final booking = bookings[index];
        final fee = booking['status'] == 'arrived'
            ? booking['cancellationFeePaise'] as int? ?? 0
            : 0;
        final accepted = body['acceptFeePaise'] as int?;
        // Apps that don't say what they agreed to (before build 9) cancel
        // free.
        if (accepted != null && fee > accepted) {
          return _json({
            'error': 'cancelling now costs a fee',
            'code': 'cancellation_fee',
            'feePaise': fee,
          }, 409);
        }
        final charged = accepted == null ? 0 : fee;
        bookings[index] = {
          ...booking,
          'status': 'cancelled',
          'cancelledAt': '2030-10-25T06:00:00Z',
          'cancelledBy': 'customer',
          'cancelReason': ?body['reason'],
          if (charged > 0) ...{
            'cancellationFeePaise': charged,
            'paymentStatus': 'due',
          },
        }..remove('startOtp');
        if (charged == 0) bookings[index].remove('cancellationFeePaise');
        return _json({'booking': bookings[index]});
      case 'end':
        if (actionError case final error?) return _error(error);
        if (bookings[index]['status'] != 'in_progress') {
          return _error((409, 'cannot_end'));
        }
        bookings[index] = {
          ...bookings[index],
          'status': 'completed',
          'completedAt': '2030-10-26T06:00:00Z',
          'farePaise': endedFarePaise,
          'bookedFarePaise': bookings[index]['farePaise'],
          'fareEstimated': false,
          'paymentStatus': 'due',
        };
        return _json({'booking': bookings[index]});
      case 'rating':
        if (actionError case final error?) return _error(error);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bookings[index] = {
          ...bookings[index],
          'myRating': {'stars': body['stars'], 'note': ?body['note']},
        };
        return _json({'booking': bookings[index]});
      case 'payment' when path.length == 4:
        if (paymentError case final error?) return _error(error);
        return _json({
          'checkout': {
            'provider': 'phonepe',
            'environment': 'SANDBOX',
            'merchantId': 'M1',
            'orderId': 'OMO1',
            'token': 'order-token',
            'merchantOrderId': 'MOJUD_b1_1',
            // A cancelled ride's checkout is for its fee; either way, plus
            // what's owed on other bookings.
            'amountPaise':
                (bookings[index]['status'] == 'cancelled'
                    ? bookings[index]['cancellationFeePaise'] as int
                    : bookings[index]['farePaise'] as int) +
                (bookings[index]['carriedPaise'] as int? ?? 0),
          },
        });
      case 'payment':
        _syncs++;
        if (paidAfterSyncs case final n? when _syncs >= n) {
          // Paying a booking that carried dues pays them all.
          final covered = (bookings[index]['carriedPaise'] as int? ?? 0) > 0;
          for (var i = 0; i < bookings.length; i++) {
            if (i != index && !covered) continue;
            final pays = i == index || bookings[i]['paymentStatus'] == 'due';
            bookings[i] = {
              ...bookings[i],
              if (pays) ...{
                'paymentStatus': 'paid',
                'paidAt': '2030-10-26T08:00:00Z',
              },
            }..remove('carriedPaise');
          }
        }
        return _json({'booking': bookings[index]});
      case 'driver-location':
        if (locationError case final error?) return _error(error);
        return _json({'location': location});
    }
    return http.Response('not found', 404);
  }
}
