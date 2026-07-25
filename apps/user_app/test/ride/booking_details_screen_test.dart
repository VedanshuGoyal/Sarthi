import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/round_trip_booking.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/booking_details_screen.dart';
import 'package:user_app/features/ride/view_model/booking_details_view_model.dart';

const _pickup = PickupLocation(
  address: 'MG Road, Bengaluru',
  point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
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
      child: MaterialApp(
        home: BookingDetailsScreen(
          pickup: _pickup,
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
    expect(find.text('MG Road, Bengaluru'), findsOneWidget); // pickup echo
    // The car dropdown awaits a pick; the gearbox defaults to automatic.
    expect(find.text('Select car type'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    // No "Select date/time" placeholder — the schedule is pre-filled.
    expect(find.text('Select date'), findsNothing);
    expect(find.text('Select time'), findsNothing);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
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

  testWidgets('the fare updates as hours and car type change', (tester) async {
    // A fixed midday start keeps the shown fares clear of the after-10pm charge.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingDetailsViewModelProvider.overrideWith(
            (ref, pickup) => BookingDetailsViewModel(
              pickup: pickup,
              initialScheduledAt: DateTime(2026, 7, 18, 12),
            ),
          ),
        ],
        child: const MaterialApp(home: BookingDetailsScreen(pickup: _pickup)),
      ),
    );

    // Standard preview at the default 2 hours (the fare carries a `*` marker).
    expect(find.textContaining('₹240'), findsOneWidget);

    // A third hour adds ₹100 at the standard rate.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹340'), findsOneWidget);

    // Luxury re-prices the same 3 hours at the premium rate (330 + 110).
    await tester.tap(find.text('Select car type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luxury').last);
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

  testWidgets('picking a car type enables confirm', (tester) async {
    await _pump(tester);

    // Disabled up front (no car), prompting for one.
    expect(find.text('Choose a car type to continue.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('Select car type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUV').last);
    await tester.pumpAndSettle();

    expect(find.text('Choose a car type to continue.'), findsNothing);
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
          bookingDetailsViewModelProvider.overrideWith(
            (ref, pickup) => BookingDetailsViewModel(
              pickup: pickup,
              initialScheduledAt: DateTime(2026, 7, 18, 12),
            ),
          ),
        ],
        child: const MaterialApp(home: BookingDetailsScreen(pickup: _pickup)),
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

    // The schedule is pre-filled, so a car type is all that's needed.
    await tester.tap(find.text('Select car type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sedan').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.pickup.address, 'MG Road, Bengaluru');
    expect(received!.scheduledAt.isAfter(DateTime.now()), isTrue);
  });
}
