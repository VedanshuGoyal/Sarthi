import 'package:flutter/foundation.dart';

import '../data/rides_repository.dart';
import '../domain/ride.dart';

/// The Earnings panel's summary: today, this week, this month, all time.
class EarningsViewModel extends ChangeNotifier {
  EarningsViewModel({required this._repository});

  final RidesRepository _repository;

  Earnings _earnings = const Earnings();
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  Earnings get earnings => _earnings;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _earnings = await _repository.earnings();
      _error = null;
    } on RidesException catch (e) {
      _error = e.message;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }
}
