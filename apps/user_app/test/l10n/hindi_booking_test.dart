// The booking side in Hindi on narrow phones: Home and its trip chooser,
// the Round Trip form and the Multi-Stop planner in each state, with the
// sheets, dialogs and snackbars they open. Fails on any layout exception.

import 'dart:async';
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
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/booking_details_screen.dart';
import 'package:user_app/features/ride/view/multi_stop_planner_screen.dart';
import 'package:user_app/features/ride/view/widgets/fare_summary.dart';
import 'package:user_app/features/ride/view/widgets/trip_option_card.dart';
import 'package:user_app/features/ride/view_model/booking_details_view_model.dart';
import 'package:user_app/features/ride/view_model/multi_stop_planner_view_model.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/features/ride/view_model/trip_selection_view_model.dart';
import 'package:user_app/features/ride/view_model/trip_start_view_model.dart';
import 'package:user_app/l10n/l10n.dart';

import '../support/fake_booking_server.dart';
import '../support/fake_location_repository.dart';
import '../support/hindi.dart';

final _user = AuthUser(
  id: 'u1',
  phoneE164: '+919876543210',
  name: 'Venkataramanathan Subramaniam',
  email: 'venkat@example.com',
  dateOfBirth: DateTime(1985),
);

const _pickup = PickupLocation(
  address:
      'Tower B, DLF Cyber Hub, DLF Cyber City, DLF Phase 2, Sector 24, '
      'Gurugram, Haryana 122002',
  point: GeoPoint(latitude: 28.4950, longitude: 77.0890),
);

const _places = [
  PickupLocation(
    address: 'Indira Gandhi International Airport Terminal 3, New Delhi 110037',
    point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
  ),
  PickupLocation(
    address: 'Passport Seva Kendra, Bhikaji Cama Place, R K Puram, New Delhi',
    point: GeoPoint(latitude: 28.5679, longitude: 77.1859),
  ),
  PickupLocation(
    address: 'Ambience Mall, National Highway 48, Ambience Island, Gurugram',
    point: GeoPoint(latitude: 28.5045, longitude: 77.0970),
  ),
];

const _cars = [
  Car(
    id: 'c1',
    registration: 'HR26DQ5551',
    type: CarType.luxury,
    transmission: Transmission.automatic,
  ),
  Car(
    id: 'c2',
    registration: 'DL01AB1234',
    type: CarType.sedan,
    transmission: Transmission.manual,
  ),
];

/// 6:30 AM, so the default starts are bookable and a 9 PM start runs into
/// the night surcharge.
final _now = DateTime(2030, 10, 26, 6, 30);

/// An unpaid finished ride, so the forms note it will be added.
final _owed = [
  MyBooking.tryParse(
    bookingJson(id: 'b0', status: 'completed', paymentStatus: 'due'),
  )!,
];

/// A GPS fix that never arrives: the pickup row stays "finding…".
class _NeverLocates extends FakeLocationRepository {
  @override
  Future<PickupLocation> currentLocation() =>
      Completer<PickupLocation>().future;
}

Override _rides({List<MyBooking> owed = const []}) =>
    myBookingsViewModelProvider.overrideWith(
      (ref) => MyBookingsViewModel(
        repository: BookingRepository(),
        initialBookings: owed,
      ),
    );

Override _savedCars() => savedCarsViewModelProvider.overrideWith(
  (ref) => SavedCarsViewModel(repository: CarsRepository(), initialCars: _cars),
);

Override _start(TripStartViewModel Function() create) =>
    tripStartViewModelProvider.overrideWith((ref) => create());

TripStartViewModel _gps() => TripStartViewModel(
  repository: FakeLocationRepository(),
  initialStart: _pickup,
);

Override _roundTrip({Car? car, int hours = 2, DateTime? at, DateTime? now}) =>
    bookingDetailsViewModelProvider.overrideWith(
      (ref) => BookingDetailsViewModel(
        initialHours: hours,
        initialScheduledAt: at,
        initialCar: car,
        clock: () => now ?? _now,
      ),
    );

Override _plan({
  List<StopDraft>? stops,
  Car? car,
  DateTime? at,
  DateTime? now,
}) => multiStopPlannerViewModelProvider.overrideWith(
  (ref, start) => MultiStopPlannerViewModel(
    start: start,
    initialScheduledAt: at ?? DateTime(2030, 10, 26, 9),
    initialStops: stops,
    initialCar: car,
    clock: () => now ?? _now,
  ),
);

/// Three long stops with long errands; [outOfOrder] makes stop 3 leave
/// before stop 2.
List<StopDraft> _stops({bool outOfOrder = false}) => [
  for (final (i, place) in _places.indexed)
    StopDraft(
      id: i,
      location: place,
      task:
          'Pick up the signed property papers from the reception desk and '
          'wait for the receipt',
      departBy: DateTime(
        2030,
        10,
        26,
        outOfOrder && i == 2 ? 10 : 11 + i * 2,
        45,
      ),
    ),
];

/// [pumpHindi] on a fresh tree, so nothing — a provider's state, a
/// snackbar — carries over from the screen pumped before.
Future<void> _pumpFresh(
  WidgetTester tester,
  Widget home, {
  required double width,
  double height = 2400,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpHindi(
    tester,
    home,
    width: width,
    height: height,
    overrides: overrides,
    settle: settle,
  );
}

void main() {
  tearDown(L10n.reset);

  for (final width in hindiWidths) {
    group('Hindi at ${width.toInt()} dp wide:', () {
      testWidgets('Home, with each trip type picked', (tester) async {
        for (final picked in [null, ...TripType.values]) {
          await _pumpFresh(
            tester,
            HomeScreen(user: _user),
            width: width,
            overrides: [
              tripSelectionViewModelProvider.overrideWith(
                (ref) => TripSelectionViewModel(initialType: picked),
              ),
            ],
          );
          checkHindiFits(tester);
          check(find.text('ड्राइवर बुक करें').evaluate()).isNotEmpty();
        }
      });

      testWidgets('Home on a short phone', (tester) async {
        await _pumpFresh(
          tester,
          HomeScreen(user: _user),
          width: width,
          height: 640,
        );
        checkHindiFits(tester);
      });

      testWidgets('Round Trip: booked, and refused with a retry', (
        tester,
      ) async {
        for (final refused in [false, true]) {
          final repository = BookingRepository(
            baseUrl: 'http://api',
            tokenGetter: () => 'tok',
            client: MockClient((request) async {
              if (request.method != 'POST') {
                return http.Response(jsonEncode({'bookings': []}), 200);
              }
              return refused
                  ? http.Response(
                      jsonEncode({
                        'error':
                            'pick a start time at least 45 minutes from now',
                      }),
                      400,
                    )
                  : http.Response(jsonEncode({'id': 'b9'}), 201);
            }),
          );
          await _pumpFresh(
            tester,
            HomeScreen(user: _user),
            width: width,
            overrides: [
              bookingRepositoryProvider.overrideWithValue(repository),
              myBookingsViewModelProvider.overrideWith(
                (ref) => MyBookingsViewModel(repository: repository),
              ),
              _savedCars(),
              _start(_gps),
              _roundTrip(car: _cars.first, hours: 12),
            ],
          );
          // The featured card is Round Trip.
          await tester.tap(find.byType(TripOptionCard).first);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SarthiPrimaryButton));
          await tester.pumpAndSettle();

          checkHindiFits(tester);
          check(
            find
                .textContaining(refused ? 'बुक नहीं हुई' : 'बुक हो गई')
                .evaluate(),
          ).isNotEmpty();
        }
      });

      testWidgets('Round Trip form: no pickup, finding it, no car, filled', (
        tester,
      ) async {
        final states = <(List<Override>, bool)>[
          // GPS gave nothing: choose a pickup.
          (
            [
              _start(
                () => TripStartViewModel(repository: FakeLocationRepository()),
              ),
              _roundTrip(),
            ],
            true,
          ),
          // Still finding the pickup.
          (
            [
              _start(
                () => TripStartViewModel(repository: _NeverLocates())..locate(),
              ),
              _roundTrip(),
            ],
            false,
          ),
          // Pickup found, no car yet.
          ([_start(_gps), _roundTrip()], true),
          // Everything picked: 12 h in the luxury car, into the night, with
          // an earlier ride's dues to add.
          (
            [
              _start(_gps),
              _roundTrip(
                car: _cars.first,
                hours: 12,
                at: DateTime(2030, 10, 26, 21),
              ),
            ],
            true,
          ),
          // A start too soon for a driver to accept.
          (
            [
              _start(_gps),
              _roundTrip(
                car: _cars.last,
                at: DateTime(2030, 10, 26, 7),
                now: DateTime(2030, 10, 26, 6, 45),
              ),
            ],
            true,
          ),
        ];
        for (final (overrides, settle) in states) {
          for (final height in const [640.0, 2400.0]) {
            await _pumpFresh(
              tester,
              const BookingDetailsScreen(),
              width: width,
              height: height,
              settle: settle,
              overrides: [
                _rides(owed: _owed),
                _savedCars(),
                ...overrides,
              ],
            );
            checkHindiFits(tester);
          }
        }
      });

      testWidgets('Round Trip: the fare note and the start-time sheet', (
        tester,
      ) async {
        await _pumpFresh(
          tester,
          const BookingDetailsScreen(),
          width: width,
          overrides: [
            _rides(),
            _savedCars(),
            _start(_gps),
            _roundTrip(car: _cars.first),
          ],
        );
        // The fare's * marker opens the note.
        await tester.tap(
          find.descendant(
            of: find.byType(FareSummary),
            matching: find.byType(InkWell),
          ),
        );
        await tester.pumpAndSettle();
        checkHindiFits(tester);
        check(find.byType(AlertDialog).evaluate()).isNotEmpty();
        await tester.tap(find.text('ठीक है'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.schedule_outlined));
        await tester.pumpAndSettle();
        checkHindiFits(tester);
        check(find.text('शुरू होने का समय चुनें').evaluate()).isNotEmpty();
      });

      testWidgets('Multi-Stop planner: blank, out of order, ready, full', (
        tester,
      ) async {
        final states = <List<Override>>[
          // One blank stop, no car.
          [_plan()],
          // Three long stops, the last leaving before the one ahead of it.
          [_plan(stops: _stops(outOfOrder: true), car: _cars.first)],
          // Ready to confirm, with dues to add.
          [_plan(stops: _stops(), car: _cars.first)],
          // All stops written but no car.
          [_plan(stops: _stops())],
          // A start too soon.
          [
            _plan(
              stops: _stops(),
              car: _cars.first,
              at: DateTime(2030, 10, 26, 7),
              now: DateTime(2030, 10, 26, 6, 45),
            ),
          ],
          // As many stops as a plan can hold.
          [
            _plan(
              stops: [
                for (var i = 0; i < MultiStopPlannerViewModel.maxStops; i++)
                  StopDraft(id: i, location: _places[i % _places.length]),
              ],
            ),
          ],
        ];
        for (final overrides in states) {
          for (final height in const [640.0, 4000.0]) {
            await _pumpFresh(
              tester,
              const MultiStopPlannerScreen(start: _pickup),
              width: width,
              height: height,
              overrides: [
                _rides(owed: _owed),
                _savedCars(),
                ...overrides,
              ],
            );
            checkHindiFits(tester);
          }
        }
      });
    });
  }
}
