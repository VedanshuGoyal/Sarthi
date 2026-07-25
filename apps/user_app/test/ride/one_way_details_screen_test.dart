import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/one_way_details_screen.dart';
import 'package:user_app/features/ride/view_model/one_way_review_view_model.dart';

const _start = PickupLocation(
  address: 'MG Road, Bengaluru',
  point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
);

const _destination = PickupLocation(
  address: 'Kempegowda International Airport, Bengaluru',
  point: GeoPoint(latitude: 13.1986, longitude: 77.7066),
);

/// Pumps the details screen. The review step it pushes gets its view model
/// seeded with [reviewTravelTime] — no estimate request is made in tests.
Future<void> _pump(
  WidgetTester tester, {
  Duration? reviewTravelTime,
  ValueChanged<OneWayTrip>? onOk,
}) {
  // A tall surface so the whole form is laid out at once.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        oneWayReviewViewModelProvider.overrideWith(
          (ref, draft) => OneWayReviewViewModel(
            draft: draft,
            initialTravelTime: reviewTravelTime,
          ),
        ),
      ],
      child: MaterialApp(
        home: OneWayDetailsScreen(
          start: _start,
          destination: _destination,
          onConfirmed: onOk == null ? null : (_, trip) => onOk(trip),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('echoes the route and disables continue until a car is picked', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('MG Road, Bengaluru'), findsOneWidget);
    expect(
      find.text('Kempegowda International Airport, Bengaluru'),
      findsOneWidget,
    );
    // The schedule is pre-filled — no placeholder.
    expect(find.text('Select date'), findsNothing);
    expect(find.text('Select time'), findsNothing);
    // No drive time is shown (or fetched) on this step.
    expect(find.text('Trip time'), findsNothing);
    // The car dropdown awaits a pick; the gearbox defaults to automatic.
    expect(find.text('Select car type'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);

    expect(find.text('Choose a car type to continue.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('choosing a car leads to the review step, whose confirm returns '
      'the trip with the estimated time', (tester) async {
    OneWayTrip? received;
    await _pump(
      tester,
      reviewTravelTime: const Duration(minutes: 50),
      onOk: (t) => received = t,
    );

    // Pick a car type from its dropdown.
    await tester.tap(find.text('Select car type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sedan').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose a car type to continue.'), findsNothing);

    // Switch the gearbox from the default automatic to manual.
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    // The review step shows the settled plan and its estimated trip time.
    expect(find.text('Review trip'), findsOneWidget);
    expect(find.text('Sedan · Manual'), findsOneWidget);
    expect(find.text('About 50 min'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.start.address, 'MG Road, Bengaluru');
    expect(
      received!.destination.address,
      'Kempegowda International Airport, Bengaluru',
    );
    expect(received!.carType, CarType.sedan);
    expect(received!.transmission, Transmission.manual);
    expect(received!.scheduledAt.isAfter(DateTime.now()), isTrue);
    expect(received!.estimatedTravelTime, const Duration(minutes: 50));
  });
}
