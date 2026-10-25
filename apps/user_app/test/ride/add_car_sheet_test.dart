import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/booking_details_screen.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/features/ride/view_model/trip_start_view_model.dart';

import '../support/fake_location_repository.dart';

const _pickup = PickupLocation(
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
);

/// A repository that saves cars in memory (or fails), without a network.
class _FakeCarsRepository extends CarsRepository {
  _FakeCarsRepository({this.failWith});

  /// When set, add() rejects with this server-style message.
  String? failWith;

  List<Car> cars = const [];

  @override
  Future<List<Car>> list() async => cars;

  @override
  Future<({Car car, List<Car> cars})> add({
    required String registration,
    required CarType type,
    required Transmission transmission,
  }) async {
    final message = failWith;
    if (message != null) throw CarsRequestException(message);
    final car = Car(
      id: 'c${cars.length + 1}',
      registration: registration,
      type: type,
      transmission: transmission,
    );
    cars = [car, ...cars];
    return (car: car, cars: cars);
  }
}

Future<void> _pump(WidgetTester tester, _FakeCarsRepository repo) {
  // A tall surface so the whole form is laid out at once.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedCarsViewModelProvider.overrideWith(
          (ref) => SavedCarsViewModel(repository: repo),
        ),
        tripStartViewModelProvider.overrideWith(
          (ref) => TripStartViewModel(
            repository: FakeLocationRepository(),
            initialStart: _pickup,
          ),
        ),
      ],
      child: const MaterialApp(home: BookingDetailsScreen()),
    ),
  );
}

void main() {
  testWidgets('adding a car from the sheet saves it and selects it', (
    tester,
  ) async {
    final repo = _FakeCarsRepository();
    await _pump(tester, repo);

    // No cars yet — only the add entry point.
    expect(find.textContaining('No saved cars yet'), findsOneWidget);
    await tester.tap(find.text('Add a car'));
    await tester.pumpAndSettle();

    // The sheet's save stays disabled until the form is complete.
    final saveButton = find.widgetWithText(SarthiPrimaryButton, 'Save car');
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: saveButton,
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.widgetWithText(SarthiTextField, 'Registration number'),
      'dl 98 zz 7777',
    );
    await tester.tap(find.text('Select car type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hatchback').last);
    await tester.pumpAndSettle();

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // The sheet closed; the saved car (normalised plate) is stored and shown
    // selected in the dropdown, ready to confirm.
    expect(find.text('Save car'), findsNothing);
    expect(repo.cars.single.registration, 'DL98ZZ7777');
    expect(find.text('DL98ZZ7777 · Hatchback · Automatic'), findsOneWidget);
    expect(find.text('Choose your car to continue.'), findsNothing);
  });

  testWidgets('a rejected save keeps the sheet open and shows the message', (
    tester,
  ) async {
    final repo = _FakeCarsRepository(failWith: 'car limit reached');
    await _pump(tester, repo);

    await tester.tap(find.text('Add a car'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(SarthiTextField, 'Registration number'),
      'DL98ZZ7777',
    );
    await tester.tap(find.text('Select car type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sedan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Save car'));
    await tester.pumpAndSettle();

    // Still on the sheet, with the server's message shown.
    expect(find.text('Save car'), findsOneWidget);
    expect(find.text('car limit reached'), findsOneWidget);
  });
}
