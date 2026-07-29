import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';
import 'package:user_app/features/profile/view/profile_screen.dart';
import 'package:user_app/features/profile/view/widgets/user_avatar.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';

final _user = AuthUser(
  id: 'u1',
  phoneE164: '+919876543210',
  name: 'Vedanshu Goyal',
  email: 'vedanshu@example.com',
  dateOfBirth: DateTime(2000, 1, 12),
);

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

/// A repository over an in-memory list (no network, no platform storage).
class _FakeCarsRepository extends CarsRepository {
  _FakeCarsRepository({this.cars = const []});

  List<Car> cars;

  @override
  Future<List<Car>> list() async => cars;

  @override
  Future<List<Car>> remove(Car car) async {
    cars = [
      for (final c in cars)
        if (c != car) c,
    ];
    return cars;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onLogout,
  List<Car> cars = const [_sedan],
}) {
  // A tall surface so the whole page (including the section below the cars
  // list) is laid out at once.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedCarsViewModelProvider.overrideWith(
          (ref) => SavedCarsViewModel(
            repository: _FakeCarsRepository(cars: cars),
            initialCars: cars,
          ),
        ),
      ],
      child: MaterialApp(
        home: ProfileScreen(user: _user, onLogout: onLogout),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the account details, formatted for reading', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Vedanshu Goyal'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('vedanshu@example.com'), findsOneWidget);
    expect(find.text('12 Jan 2000'), findsOneWidget);
    // The avatar carries the customer's initials.
    expect(find.text('VG'), findsOneWidget);
  });

  testWidgets('lists the saved cars with the add entry point', (tester) async {
    await _pump(tester);

    expect(find.text('My cars'), findsOneWidget);
    expect(find.text('DL01AB1234'), findsOneWidget);
    expect(find.text('Sedan · Manual'), findsOneWidget);
    expect(find.text('Add a car'), findsOneWidget);
  });

  testWidgets('with no cars, the list gives way to the empty prompt', (
    tester,
  ) async {
    await _pump(tester, cars: const []);

    expect(find.textContaining('No saved cars yet'), findsOneWidget);
    expect(find.text('Add a car'), findsOneWidget);
  });

  testWidgets('the delete action removes the car', (tester) async {
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('DL01AB1234'), findsNothing);
    expect(find.textContaining('No saved cars yet'), findsOneWidget);
  });

  testWidgets('tapping Add a car opens the add-car sheet', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Add a car'));
    await tester.pumpAndSettle();

    expect(find.text('Registration number'), findsOneWidget);
    expect(find.text('Save car'), findsOneWidget);
  });

  testWidgets('tapping Log out emits the event', (tester) async {
    var loggedOut = false;
    await _pump(tester, onLogout: () => loggedOut = true);

    await tester.tap(find.text('Log out'));
    await tester.pump();

    expect(loggedOut, isTrue);
  });

  testWidgets('without a logout handler the button is absent', (tester) async {
    await _pump(tester);

    expect(find.text('Log out'), findsNothing);
  });

  test('initials cover full names, single names, and blanks', () {
    expect(UserAvatar.initials('Vedanshu Goyal'), 'VG');
    expect(UserAvatar.initials('Priya'), 'P');
    expect(UserAvatar.initials('A P J Abdul Kalam'), 'AK');
    expect(UserAvatar.initials('   '), '?');
  });
}
