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
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/features/ride/view_model/trip_start_view_model.dart';

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

void main() {
  testWidgets(
    "a booking the server refuses says it wasn't booked, and why, then retries",
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The first submission is refused the way the server refuses a start
      // that's become too soon; the retry goes through.
      final posts = <http.Request>[];
      final repository = BookingRepository(
        baseUrl: 'http://api',
        tokenGetter: () => 'tok',
        client: MockClient((request) async {
          if (request.method != 'POST') {
            return http.Response(jsonEncode({'bookings': []}), 200);
          }
          posts.add(request);
          return posts.length == 1
              ? http.Response(
                  jsonEncode({
                    'error': 'pick a start time at least 45 minutes from now',
                  }),
                  400,
                )
              : http.Response(jsonEncode({'id': 'b1'}), 201);
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookingRepositoryProvider.overrideWithValue(repository),
            myBookingsViewModelProvider.overrideWith(
              (ref) => MyBookingsViewModel(
                repository: repository,
                initialBookings: const [],
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
      await tester.tap(
        find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
      );
      await tester.pumpAndSettle();

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
      expect(
        find.text('Round Trip booked: 2 hours, in your DL01AB1234.'),
        findsOneWidget,
      );
    },
  );
}
