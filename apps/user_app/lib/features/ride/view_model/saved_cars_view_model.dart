import 'package:flutter/foundation.dart';

import '../data/cars_repository.dart';
import '../domain/car.dart';
import '../domain/car_type.dart';
import '../domain/transmission.dart';

/// Drives the customer's saved cars: the dropdown the booking steps share and
/// the "My cars" management on the profile screen (add and remove).
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the list's load/save
/// state and talks only to [CarsRepository] (which serves reads from the
/// on-device mirror). Which car is *selected* for a trip belongs to each
/// booking step's own view model — this one only supplies the choices.
class SavedCarsViewModel extends ChangeNotifier {
  /// [initialCars] lets previews and tests start with a seeded list (and skip
  /// [load]); production starts empty and fetches.
  SavedCarsViewModel({
    required this._repository,
    List<Car> initialCars = const [],
  }) : _cars = initialCars;

  final CarsRepository _repository;

  List<Car> _cars;

  /// The customer's saved cars, newest first.
  List<Car> get cars => _cars;

  bool _isLoading = false;

  /// True while the initial list request is in flight.
  bool get isLoading => _isLoading;

  bool _loadFailed = false;

  /// True when the last list request failed — the view offers a retry.
  bool get loadFailed => _loadFailed;

  bool _isSaving = false;

  /// True while an add-car request is in flight.
  bool get isSaving => _isSaving;

  Car? _removing;

  /// The car whose removal is in flight, or null. Lets the list disable just
  /// that row's delete affordance.
  Car? get removing => _removing;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Fetches the saved cars. Called once when the provider builds; also the
  /// retry after a failed load.
  Future<void> load() async {
    _isLoading = true;
    _loadFailed = false;
    notifyListeners();

    try {
      final cars = await _repository.list();
      if (_disposed) return;
      _cars = cars;
    } on Exception {
      if (_disposed) return;
      _loadFailed = true;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Saves a car and returns it as stored (normalised plate, backend id), or
  /// throws [CarsRequestException] with a user-showable message. The list is
  /// refreshed from the response, so the new car is immediately offered.
  Future<Car> addCar({
    required String registration,
    required CarType type,
    required Transmission transmission,
  }) async {
    _isSaving = true;
    notifyListeners();
    try {
      final result = await _repository.add(
        registration: registration,
        type: type,
        transmission: transmission,
      );
      if (!_disposed) _cars = result.cars;
      return result.car;
    } finally {
      if (!_disposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// Removes [car], or throws [CarsRequestException] with a user-showable
  /// message. The list is refreshed from the response.
  Future<void> removeCar(Car car) async {
    if (_removing != null) return;
    _removing = car;
    notifyListeners();
    try {
      final cars = await _repository.remove(car);
      if (!_disposed) _cars = cars;
    } finally {
      if (!_disposed) {
        _removing = null;
        notifyListeners();
      }
    }
  }
}
