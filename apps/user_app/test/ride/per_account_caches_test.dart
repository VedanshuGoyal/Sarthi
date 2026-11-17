import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/auth/auth_controller.dart';
import 'package:user_app/features/auth/data/session_storage.dart';
import 'package:user_app/features/auth/domain/auth_session.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';
import 'package:user_app/features/ride/data/recent_locations_storage.dart';
import 'package:user_app/features/ride/data/saved_cars_storage.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

const _home = PickupLocation(
  address: '12 Rajpur Road, Delhi',
  point: GeoPoint(latitude: 28.68, longitude: 77.22),
);

AuthSession _session(String id) => AuthSession(
  token: 'tok-$id',
  user: AuthUser(
    id: id,
    phoneE164: '+919876543210',
    name: 'User $id',
    email: '$id@example.com',
    dateOfBirth: DateTime(1990),
  ),
);

class _Sessions implements SessionStorage {
  _Sessions(this._session);
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('each account on the phone keeps its own saved cars', () async {
    await SecureSavedCarsStorage(userId: 'a').write([_sedan]);

    check(await SecureSavedCarsStorage(userId: 'b').read()).isEmpty();
    check(
      await SecureSavedCarsStorage(userId: 'a').read(),
    ).deepEquals([_sedan]);
  });

  test(
    "the next account signed in isn't shown the last one's pickups",
    () async {
      await SecureRecentLocationsStorage(userId: 'a').write([_home]);
      final container = ProviderContainer(
        overrides: [sessionStorageProvider.overrideWithValue(_Sessions(null))],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final auth = container.read(authControllerProvider.notifier);

      await auth.signIn(_session('a'));
      final mine = await container
          .read(locationRepositoryProvider)
          .cachedRecents();
      check(mine.map((p) => p.address)).deepEquals([_home.address]);

      await auth.signOut();
      await auth.signIn(_session('b'));
      check(
        await container.read(locationRepositoryProvider).cachedRecents(),
      ).isEmpty();
    },
  );
}
