import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/cars_api.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/data/saved_cars_storage.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/transmission.dart';

const _sedan = Car(
  id: 'c1',
  registration: 'DL01AB1234',
  type: CarType.sedan,
  transmission: Transmission.manual,
);

const _suv = Car(
  id: 'c2',
  registration: 'DL05MN0007',
  type: CarType.suv,
  transmission: Transmission.automatic,
);

/// A backend stand-in holding a canned list; counts calls so tests can assert
/// the cache actually short-circuits the network.
class _FakeCarsApi extends CarsApi {
  _FakeCarsApi({this.cars = const []});

  List<Car> cars;
  int listCalls = 0;

  @override
  Future<List<Car>> list() async {
    listCalls++;
    return cars;
  }

  @override
  Future<({Car car, List<Car> cars})> add({
    required String registration,
    required CarType type,
    required Transmission transmission,
  }) async {
    final car = Car(
      id: 'c${cars.length + 1}',
      registration: registration,
      type: type,
      transmission: transmission,
    );
    cars = [car, ...cars];
    return (car: car, cars: cars);
  }

  @override
  Future<List<Car>> remove(String id) async {
    cars = [
      for (final car in cars)
        if (car.id != id) car,
    ];
    return cars;
  }
}

/// In-memory storage stand-in.
class _FakeStorage implements SavedCarsStorage {
  List<Car> stored = const [];

  @override
  Future<List<Car>> read() async => stored;

  @override
  Future<void> write(List<Car> cars) async => stored = cars;
}

void main() {
  group('CarsRepository', () {
    test('serves the list from storage without touching the API', () async {
      final api = _FakeCarsApi(cars: const [_suv]);
      final storage = _FakeStorage()..stored = const [_sedan];
      final repo = CarsRepository(api: api, storage: storage);

      final cars = await repo.list();

      check(cars).deepEquals(const [_sedan]);
      check(api.listCalls).equals(0);
    });

    test('an empty cache is filled once from the API', () async {
      final api = _FakeCarsApi(cars: const [_sedan, _suv]);
      final storage = _FakeStorage();
      final repo = CarsRepository(api: api, storage: storage);

      final cars = await repo.list();
      check(cars).deepEquals(const [_sedan, _suv]);
      check(storage.stored).deepEquals(const [_sedan, _suv]);

      // The mirror now serves the next read.
      await repo.list();
      check(api.listCalls).equals(1);
    });

    test('add writes through to the API and mirrors the result', () async {
      final api = _FakeCarsApi(cars: const [_sedan]);
      final storage = _FakeStorage()..stored = const [_sedan];
      final repo = CarsRepository(api: api, storage: storage);

      final result = await repo.add(
        registration: 'DL05MN0007',
        type: CarType.suv,
        transmission: Transmission.automatic,
      );

      check(result.car.registration).equals('DL05MN0007');
      check(storage.stored.length).equals(2);
      check(storage.stored.first).equals(result.car);
    });

    test('remove writes through to the API and mirrors the result', () async {
      final api = _FakeCarsApi(cars: const [_sedan, _suv]);
      final storage = _FakeStorage()..stored = const [_sedan, _suv];
      final repo = CarsRepository(api: api, storage: storage);

      final cars = await repo.remove(_sedan);

      check(cars).deepEquals(const [_suv]);
      check(storage.stored).deepEquals(const [_suv]);
    });
  });
}
