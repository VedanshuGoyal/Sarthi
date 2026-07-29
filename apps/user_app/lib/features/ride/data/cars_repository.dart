import '../domain/car.dart';
import '../domain/car_type.dart';
import '../domain/transmission.dart';
import 'cars_api.dart';
import 'saved_cars_storage.dart';

export 'cars_api.dart' show CarsRequestException;

/// The sole data-access seam for the customer's saved cars, per the repository
/// guideline.
///
/// Reads are local-first: the list lives in on-device storage, so opening a
/// booking step or the profile costs no API call. The backend (PostgreSQL)
/// stays the source of truth — every change (add, remove) writes through to it
/// and the response is mirrored back into storage. The network is only touched
/// for those writes, or once to fill an empty cache (fresh install / new
/// device).
class CarsRepository {
  CarsRepository({CarsApi? api, SavedCarsStorage? storage})
    : _api = api ?? CarsApi(),
      _storage = storage ?? SecureSavedCarsStorage();

  final CarsApi _api;
  final SavedCarsStorage _storage;

  /// The user's saved cars, newest first — from on-device storage when it has
  /// any, otherwise fetched once from the backend and mirrored locally.
  Future<List<Car>> list() async {
    final cached = await _storage.read();
    if (cached.isNotEmpty) return cached;

    final cars = await _api.list();
    if (cars.isNotEmpty) await _storage.write(cars);
    return cars;
  }

  /// Saves a car to the backend, mirrors the updated list locally, and returns
  /// the stored car (normalised registration, backend id) with that list.
  Future<({Car car, List<Car> cars})> add({
    required String registration,
    required CarType type,
    required Transmission transmission,
  }) async {
    final result = await _api.add(
      registration: registration,
      type: type,
      transmission: transmission,
    );
    await _storage.write(result.cars);
    return result;
  }

  /// Removes [car] from the backend, mirrors the updated list locally, and
  /// returns it.
  Future<List<Car>> remove(Car car) async {
    final cars = await _api.remove(car.id);
    await _storage.write(cars);
    return cars;
  }
}
