import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/round_trip_booking.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/booking_details_screen.dart';
import 'package:user_app/features/ride/view_model/booking_details_view_model.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/features/ride/view_model/trip_start_view_model.dart';

import '../support/fake_location_repository.dart';

const _pickup = PickupLocation(
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
);

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

const _luxury = Car(
  id: 'c2',
  registration: 'DL53LX9000',
  type: CarType.luxury,
  transmission: Transmission.automatic,
);

/// Fills the pickup row as if GPS had found [_pickup], without the plugin.
Override _gpsPickup() => tripStartViewModelProvider.overrideWith(
  (ref) => TripStartViewModel(
    repository: FakeLocationRepository(),
    initialStart: _pickup,
  ),
);

/// Seeds the saved-car dropdown so no network request is made. The repository
/// is never invoked — the seeded state skips the load.
Override _savedCars({List<Car> cars = const [_sedan, _luxury]}) =>
    savedCarsViewModelProvider.overrideWith(
      (ref) =>
          SavedCarsViewModel(repository: CarsRepository(), initialCars: cars),
    );

Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<RoundTripBooking>? onOk,
}) {
  // A tall surface so the whole scrolling form is laid out at once, letting the
  // test read and tap any section without scrolling.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    ProviderScope(
      overrides: [_savedCars(), _gpsPickup()],
      child: MaterialApp(
        home: BookingDetailsScreen(
          onConfirmed: onOk == null ? null : (_, booking) => onOk(booking),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the options and disables confirm until a car is picked', (
    tester,
  ) async {
    await _pump(tester);

    // Every requested control is on screen.
    expect(
      find.text('Connaught Place, New Delhi'),
      findsOneWidget,
    ); // pickup echo
    // The saved-car dropdown awaits a pick, with the add-car entry point.
    expect(find.text('Select your car'), findsOneWidget);
    expect(find.text('Add a car'), findsOneWidget);
    // No "Select date/time" placeholder — the schedule is pre-filled.
    expect(find.text('Select date'), findsNothing);
    expect(find.text('Select time'), findsNothing);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('with no saved cars, the dropdown gives way to the add prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [_savedCars(cars: const [])],
        child: const MaterialApp(home: BookingDetailsScreen()),
      ),
    );

    expect(find.text('Select your car'), findsNothing);
    expect(find.textContaining('No saved cars yet'), findsOneWidget);
    expect(find.text('Add a car'), findsOneWidget);
  });

  testWidgets('the hours stepper increments the shown duration', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the fare updates as hours and car change', (tester) async {
    // A fixed midday start keeps the shown fares clear of the after-10pm charge.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _savedCars(),
          _gpsPickup(),
          bookingDetailsViewModelProvider.overrideWith(
            (ref) => BookingDetailsViewModel(
              initialScheduledAt: DateTime(2026, 7, 18, 12),
            ),
          ),
        ],
        child: const MaterialApp(home: BookingDetailsScreen()),
      ),
    );

    // Standard preview at the default 2 hours (the fare carries a `*` marker).
    expect(find.textContaining('₹240'), findsOneWidget);

    // A third hour adds ₹100 at the standard rate.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹340'), findsOneWidget);

    // The luxury car re-prices the same 3 hours at the premium rate (330 + 110).
    await tester.tap(find.text('Select your car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DL53LX9000 · Luxury · Automatic').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('₹440'), findsOneWidget);
  });

  testWidgets('tapping the fare marker explains that prices may vary', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Prices may vary'), findsNothing);
    await tester.tap(find.textContaining('*'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prices may vary'), findsOneWidget);
  });

  testWidgets('picking a saved car enables confirm', (tester) async {
    await _pump(tester);

    // Disabled up front (no car), prompting for one.
    expect(find.text('Choose your car to continue.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('Select your car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DL01AB1234 · Sedan · Manual').last);
    await tester.pumpAndSettle();

    expect(find.text('Choose your car to continue.'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('the time field offers only quarter-hour slots', (tester) async {
    // A fixed midday start makes the built slots deterministic.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _savedCars(),
          _gpsPickup(),
          bookingDetailsViewModelProvider.overrideWith(
            (ref) => BookingDetailsViewModel(
              initialScheduledAt: DateTime(2026, 7, 18, 12),
              clock: () => DateTime(2026, 7, 18, 9),
            ),
          ),
        ],
        child: const MaterialApp(home: BookingDetailsScreen()),
      ),
    );

    await tester.tap(find.widgetWithText(InkWell, '12:00 PM'));
    await tester.pumpAndSettle();
    expect(find.text('Trips start every 15 minutes.'), findsOneWidget);

    await tester.tap(find.text('12:15 PM'));
    await tester.pumpAndSettle();

    // The sheet closed and the schedule field shows the picked slot.
    expect(find.text('Trips start every 15 minutes.'), findsNothing);
    expect(find.text('12:15 PM'), findsOneWidget);
  });

  testWidgets('confirming returns the assembled booking', (tester) async {
    RoundTripBooking? received;
    await _pump(tester, onOk: (b) => received = b);

    // The schedule is pre-filled, so a car is all that's needed.
    await tester.tap(find.text('Select your car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DL01AB1234 · Sedan · Manual').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.pickup.address, 'Connaught Place, New Delhi');
    expect(received!.car, _sedan);
    expect(received!.scheduledAt.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('the pickup row shows the GPS spot, tappable to change', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.text('Pickup · tap to change'), findsOneWidget);
  });

  testWidgets('without a pickup, confirm waits for one', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _savedCars(),
          // GPS found nothing usable (never located, no remembered spot).
          tripStartViewModelProvider.overrideWith(
            (ref) => TripStartViewModel(repository: FakeLocationRepository()),
          ),
          bookingDetailsViewModelProvider.overrideWith(
            (ref) => BookingDetailsViewModel(initialCar: _sedan),
          ),
        ],
        child: const MaterialApp(home: BookingDetailsScreen()),
      ),
    );

    expect(find.text('Choose a pickup'), findsOneWidget);
    expect(find.text('Choose your pickup to continue.'), findsOneWidget);
    final confirm = tester.widget<SarthiPrimaryButton>(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('changing the pickup keeps the other choices', (tester) async {
    RoundTripBooking? received;
    await _pump(tester, onOk: (b) => received = b);
    await tester.tap(find.text('Select your car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DL01AB1234 · Sedan · Manual').last);
    await tester.pumpAndSettle();

    const elsewhere = PickupLocation(
      address: 'Khan Market, New Delhi',
      point: GeoPoint(latitude: 28.6003, longitude: 77.2270),
    );
    ProviderScope.containerOf(
      tester.element(find.byType(BookingDetailsScreen)),
    ).read(tripStartViewModelProvider).setStart(elsewhere);
    await tester.pumpAndSettle();
    expect(find.text('Khan Market, New Delhi'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    await tester.pumpAndSettle();
    expect(received!.pickup.address, 'Khan Market, New Delhi');
    expect(received!.car, _sedan);
  });
}
