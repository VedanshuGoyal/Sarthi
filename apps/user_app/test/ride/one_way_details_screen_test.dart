import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/one_way_details_screen.dart';
import 'package:user_app/features/ride/view_model/one_way_review_view_model.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';

const _start = PickupLocation(
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
);

const _destination = PickupLocation(
  address: 'Indira Gandhi International Airport, New Delhi',
  point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
);

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

/// Pumps the details screen with the saved-car dropdown seeded (no network).
/// The review step it pushes gets its view model seeded with
/// [reviewTravelTime] — no estimate request is made in tests.
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
        savedCarsViewModelProvider.overrideWith(
          (ref) => SavedCarsViewModel(
            repository: CarsRepository(),
            initialCars: const [_sedan],
          ),
        ),
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

    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(
      find.text('Indira Gandhi International Airport, New Delhi'),
      findsOneWidget,
    );
    // The schedule is pre-filled — no placeholder.
    expect(find.text('Select date'), findsNothing);
    expect(find.text('Select time'), findsNothing);
    // No drive time is shown (or fetched) on this step.
    expect(find.text('Trip time'), findsNothing);
    // The saved-car dropdown awaits a pick, with the add-car entry point.
    expect(find.text('Select your car'), findsOneWidget);
    expect(find.text('Add a car'), findsOneWidget);

    expect(find.text('Choose your car to continue.'), findsOneWidget);
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

    // Pick the saved car from its dropdown.
    await tester.tap(find.text('Select your car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DL01AB1234 · Sedan · Manual').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose your car to continue.'), findsNothing);

    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    // The review step shows the settled plan and its estimated trip time.
    expect(find.text('Review trip'), findsOneWidget);
    expect(find.text('DL01AB1234 · Sedan · Manual'), findsOneWidget);
    expect(find.text('About 50 min'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.start.address, 'Connaught Place, New Delhi');
    expect(
      received!.destination.address,
      'Indira Gandhi International Airport, New Delhi',
    );
    expect(received!.car, _sedan);
    expect(received!.scheduledAt.isAfter(DateTime.now()), isTrue);
    expect(received!.estimatedTravelTime, const Duration(minutes: 50));
  });
}
