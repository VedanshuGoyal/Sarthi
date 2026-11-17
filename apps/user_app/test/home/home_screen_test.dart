import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';
import 'package:user_app/features/home/view/home_screen.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/ride_details_screen.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/features/ride/view_model/trip_start_view_model.dart';

import '../support/fake_booking_server.dart';
import '../support/fake_location_repository.dart';

final _user = AuthUser(
  id: 'u1',
  phoneE164: '+919876543210',
  name: 'Asha Sharma',
  email: 'asha@example.com',
  dateOfBirth: DateTime(1995),
);

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

/// Pumps the Home tab over a backend that answers each booking POST with
/// [answer] (given how many have arrived so far) and lists [bookings], then
/// books a two-hour Round Trip through the real flow. With [listLoaded] the
/// rides list already holds [bookings], as after Activity has loaded.
Future<void> _bookRoundTrip(
  WidgetTester tester, {
  required List<http.Request> posts,
  required http.Response Function(int count) answer,
  List<Map<String, dynamic>> bookings = const [],
  bool listLoaded = false,
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = BookingRepository(
    baseUrl: 'http://api',
    tokenGetter: () => 'tok',
    client: MockClient((request) async {
      if (request.method != 'POST') {
        return http.Response(jsonEncode({'bookings': bookings}), 200);
      }
      // Opening a due ride re-checks its payment; that's not a booking.
      if (request.url.path.endsWith('/payment/sync')) {
        return http.Response(jsonEncode(bookings.first), 200);
      }
      posts.add(request);
      return answer(posts.length);
    }),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(repository),
        myBookingsViewModelProvider.overrideWith(
          (ref) => MyBookingsViewModel(
            repository: repository,
            initialBookings: listLoaded
                ? [for (final b in bookings) MyBooking.tryParse(b)!]
                : const [],
          ),
        ),
        savedCarsViewModelProvider.overrideWith(
          (ref) => SavedCarsViewModel(
            repository: CarsRepository(),
            initialCars: const [_sedan],
          ),
        ),
        tripStartViewModelProvider.overrideWith(
          (ref) => TripStartViewModel(
            repository: FakeLocationRepository(),
            initialStart: const PickupLocation(
              address: 'Connaught Place, New Delhi',
              point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
            ),
          ),
        ),
      ],
      child: MaterialApp(home: HomeScreen(user: _user)),
    ),
  );

  await tester.tap(find.text('Round Trip'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select your car'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('DL01AB1234 · Sedan · Manual').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    "a booking the server refuses says it wasn't booked, and why, then retries",
    (tester) async {
      // The first submission is refused the way the server refuses a start
      // that's become too soon; the retry goes through.
      final posts = <http.Request>[];
      await _bookRoundTrip(
        tester,
        posts: posts,
        answer: (count) => count == 1
            ? http.Response(
                jsonEncode({
                  'error': 'pick a start time at least 45 minutes from now',
                }),
                400,
              )
            : http.Response(jsonEncode({'id': 'b1'}), 201),
      );

      check(posts).length.equals(1);
      expect(find.textContaining('booked:'), findsNothing);
      expect(
        find.text(
          "Your Round Trip wasn't booked. Pick a start time at least 45 "
          'minutes from now.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      check(posts).length.equals(2);
      check(posts.last.body).equals(posts.first.body);
      // The retry is the same attempt, so the server can't book it twice.
      final key = posts.first.headers['Idempotency-Key'];
      check(key).isNotNull().isNotEmpty();
      check(posts.last.headers['Idempotency-Key']).equals(key);
      expect(
        find.text('Round Trip booked: 2 hours, in your DL01AB1234.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a repeat the server already had still reads as booked', (
    tester,
  ) async {
    final posts = <http.Request>[];
    await _bookRoundTrip(
      tester,
      posts: posts,
      answer: (_) => http.Response(
        jsonEncode({'id': 'b1', 'status': 'received', 'duplicate': true}),
        200,
      ),
    );
    check(posts).length.equals(1);
    expect(
      find.text('Round Trip booked: 2 hours, in your DL01AB1234.'),
      findsOneWidget,
    );
  });

  testWidgets('an unpaid ride blocks booking and Pay now opens that ride', (
    tester,
  ) async {
    final posts = <http.Request>[];
    await _bookRoundTrip(
      tester,
      posts: posts,
      answer: (_) => http.Response(
        jsonEncode({
          'error': 'pay for your last ride before booking another',
          'code': 'payment_due',
          'bookingId': 'unpaid-1',
        }),
        409,
      ),
      bookings: [
        bookingJson(
          id: 'unpaid-1',
          status: 'completed',
          paymentStatus: 'due',
          scheduledAt: '2030-10-20T05:00:00Z',
        ),
      ],
    );

    expect(
      find.text('Pay for your last ride before booking another.'),
      findsOneWidget,
    );
    expect(find.textContaining("wasn't booked"), findsNothing);
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.text('Pay now'));
    await tester.pumpAndSettle();

    check(find.byType(RideDetailsScreen).evaluate()).isNotEmpty();
    expect(find.text('Pay ₹640 by UPI'), findsOneWidget);
    // Paying isn't booking: nothing more was posted.
    check(posts).length.equals(1);
  });

  for (final listLoaded in [true, false]) {
    testWidgets('an unpaid cancellation fee blocks booking, and Pay now opens '
        'that ride (list ${listLoaded ? 'loaded' : 'not loaded'})', (
      tester,
    ) async {
      final posts = <http.Request>[];
      await _bookRoundTrip(
        tester,
        posts: posts,
        answer: (_) => http.Response(
          jsonEncode({
            'error': 'pay for your last ride before booking another',
            'code': 'payment_due',
            'bookingId': 'fee-1',
          }),
          409,
        ),
        bookings: [
          bookingJson(
            id: 'fee-1',
            status: 'cancelled',
            cancellationFeePaise: 5000,
            paymentStatus: 'due',
            scheduledAt: '2030-10-20T05:00:00Z',
          ),
        ],
        listLoaded: listLoaded,
      );

      // Named for what it is once the list knows the ride.
      expect(
        find.text(
          listLoaded
              ? 'Pay the ₹50 cancellation fee for your last ride before '
                    'booking another.'
              : 'Pay for your last ride before booking another.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining("wasn't booked"), findsNothing);

      await tester.tap(find.text('Pay now'));
      await tester.pumpAndSettle();

      check(find.byType(RideDetailsScreen).evaluate()).isNotEmpty();
      expect(find.text('Ride cancelled'), findsOneWidget);
      expect(find.text('Pay the cancellation fee'), findsOneWidget);
      expect(find.text('Pay ₹50 by UPI'), findsOneWidget);
      check(posts).length.equals(1);
    });
  }
}
