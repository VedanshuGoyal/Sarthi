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
  String? completedAt,
  String? cancelReason,
  String? paymentStatus,
}) => {
  'id': id,
  'tripType': tripType,
  'status': status,
  'scheduledAt': scheduledAt,
  'endsAt': '2030-10-26T07:30:00Z',
  'farePaise': 64000,
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
  'completedAt': ?completedAt,
  if (status == 'cancelled') ...{
    'cancelledAt': '2030-10-25T06:00:00Z',
    'cancelledBy': 'customer',
    'cancelReason': ?cancelReason,
  },
  'myRating': ?myRating,
  'paymentStatus': ?paymentStatus,
};

/// An in-memory stand-in for the booking endpoints, so repository, view
/// model and screen tests run the real request/parse code with no network.
///
/// [bookings] is what `GET /me/bookings` lists; cancel and rating rewrite
/// the stored booking like the server does. [location] is the driver fix
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
        bookings[index] = {
          ...bookings[index],
          'status': 'cancelled',
          'cancelledAt': '2030-10-25T06:00:00Z',
          'cancelledBy': 'customer',
          'cancelReason': ?body['reason'],
        }..remove('startOtp');
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
            'amountPaise': bookings[index]['farePaise'],
          },
        });
      case 'payment':
        _syncs++;
        if (paidAfterSyncs case final n? when _syncs >= n) {
          bookings[index] = {
            ...bookings[index],
            'paymentStatus': 'paid',
            'paidAt': '2030-10-26T08:00:00Z',
          };
        }
        return _json({'booking': bookings[index]});
      case 'driver-location':
        if (locationError case final error?) return _error(error);
        return _json({'location': location});
    }
    return http.Response('not found', 404);
  }
}
