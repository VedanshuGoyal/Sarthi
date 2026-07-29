import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';

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

/// A repository answering with canned data (or failing), without a network.
class _FakeCarsRepository extends CarsRepository {
  _FakeCarsRepository({this.cars = const [], this.fail = false});

  List<Car> cars;
  bool fail;
  int listCalls = 0;

  @override
  Future<List<Car>> list() async {
    listCalls++;
    if (fail) throw const CarsRequestException('down');
    return cars;
  }

  @override
  Future<({Car car, List<Car> cars})> add({
    required String registration,
    required CarType type,
    required Transmission transmission,
  }) async {
    if (fail) throw const CarsRequestException('down');
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
  Future<List<Car>> remove(Car car) async {
    if (fail) throw const CarsRequestException('down');
    cars = [
      for (final c in cars)
        if (c != car) c,
    ];
    return cars;
  }
}

void main() {
  group('SavedCarsViewModel', () {
    test('load fetches the list and clears the loading flag', () async {
      final vm = SavedCarsViewModel(
        repository: _FakeCarsRepository(cars: const [_sedan, _suv]),
      );
      check(vm.cars).isEmpty();

      final pending = vm.load();
      check(vm.isLoading).isTrue();
      await pending;

      check(vm.isLoading).isFalse();
      check(vm.loadFailed).isFalse();
      check(vm.cars).deepEquals(const [_sedan, _suv]);
    });

    test('a failed load flags the error; a retry clears it', () async {
      final repo = _FakeCarsRepository(cars: const [_sedan], fail: true);
      final vm = SavedCarsViewModel(repository: repo);

      await vm.load();
      check(vm.loadFailed).isTrue();
      check(vm.cars).isEmpty();

      repo.fail = false;
      await vm.load();
      check(vm.loadFailed).isFalse();
      check(vm.cars).deepEquals(const [_sedan]);
      check(repo.listCalls).equals(2);
    });

    test('addCar returns the stored car and refreshes the list', () async {
      final vm = SavedCarsViewModel(
        repository: _FakeCarsRepository(cars: const [_sedan]),
      );
      await vm.load();

      final added = await vm.addCar(
        registration: 'DL05MN0007',
        type: CarType.suv,
        transmission: Transmission.automatic,
      );

      check(added.registration).equals('DL05MN0007');
      check(vm.isSaving).isFalse();
      check(vm.cars.first).equals(added);
      check(vm.cars.length).equals(2);
    });

    test('a failed addCar rethrows and keeps the list', () async {
      final repo = _FakeCarsRepository(cars: const [_sedan]);
      final vm = SavedCarsViewModel(repository: repo);
      await vm.load();

      repo.fail = true;
      String? message;
      try {
        await vm.addCar(
          registration: 'DL05MN0007',
          type: CarType.suv,
          transmission: Transmission.automatic,
        );
      } on CarsRequestException catch (e) {
        message = e.message;
      }

      check(message).equals('down');
      check(vm.isSaving).isFalse();
      check(vm.cars).deepEquals(const [_sedan]);
    });

    test('removeCar drops the car and clears the in-flight marker', () async {
      final vm = SavedCarsViewModel(
        repository: _FakeCarsRepository(cars: const [_sedan, _suv]),
      );
      await vm.load();

      final pending = vm.removeCar(_sedan);
      check(vm.removing).equals(_sedan);
      await pending;

      check(vm.removing).isNull();
      check(vm.cars).deepEquals(const [_suv]);
    });

    test('a failed removeCar rethrows and keeps the list', () async {
      final repo = _FakeCarsRepository(cars: const [_sedan]);
      final vm = SavedCarsViewModel(repository: repo);
      await vm.load();

      repo.fail = true;
      String? message;
      try {
        await vm.removeCar(_sedan);
      } on CarsRequestException catch (e) {
        message = e.message;
      }

      check(message).equals('down');
      check(vm.removing).isNull();
      check(vm.cars).deepEquals(const [_sedan]);
    });

    test('honours seeded initial cars without fetching', () {
      final repo = _FakeCarsRepository();
      final vm = SavedCarsViewModel(
        repository: repo,
        initialCars: const [_suv],
      );
      check(vm.cars).deepEquals(const [_suv]);
      check(repo.listCalls).equals(0);
    });
  });
}
