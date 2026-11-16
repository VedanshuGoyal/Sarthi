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

  /// Re-reads the summary. Only the latest load's answer is used, so a slow
  /// one from before a ride was completed can't put the old totals back.
  Future<void> load() async {
    final seq = ++_loadSeq;
    _isLoading = true;
    _notify();
    try {
      final earnings = await _repository.earnings();
      if (seq != _loadSeq) return;
      _earnings = earnings;
      _error = null;
    } on RidesException catch (e) {
      if (seq == _loadSeq) _error = e.message;
    } finally {
      if (seq == _loadSeq) {
        _isLoading = false;
        _hasLoaded = true;
        _notify();
      }
    }
  }

  int _loadSeq = 0;
  bool _disposed = false;

  /// Notifies only while alive: a different driver signing in replaces this
  /// view model while a load may still be in flight.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
