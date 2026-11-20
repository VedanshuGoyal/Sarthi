import 'package:flutter/foundation.dart';

import '../../../core/refresh_throttle.dart';
import '../data/rides_repository.dart';
import '../domain/payout.dart';
import '../domain/ride.dart';

/// The Earnings panel's summary — today, this week, this month, all time —
/// and the bank transfers MOJUD has made to the driver.
class EarningsViewModel extends ChangeNotifier {
  EarningsViewModel({required this._repository, Clock? now})
    : _fetched = RefreshThrottle(now: now);

  final RidesRepository _repository;
  final RefreshThrottle _fetched;

  Earnings _earnings = const Earnings();
  List<Payout> _payouts = const [];
  bool _payoutsLoaded = false;
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  Earnings get earnings => _earnings;

  /// Recorded payouts, newest first.
  List<Payout> get payouts => _payouts;

  /// Whether [payouts] has been read at least once. Until it has (the list
  /// failed to load), the panel leaves the section out rather than claim
  /// there are none.
  bool get payoutsLoaded => _payoutsLoaded;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  /// Why the summary couldn't be loaded. A payouts list that fails on its
  /// own isn't reported here: the summary is what the panel is for.
  String? get error => _error;

  /// Re-reads the summary and the payouts. Only the latest load's answer is
  /// used, so a slow one from before a ride was completed can't put the old
  /// totals back. A payouts failure keeps the last list it had.
  Future<void> load() async {
    final seq = ++_loadSeq;
    _fetched.mark();
    _isLoading = true;
    _notify();
    final payouts = _fetchPayouts();
    try {
      final earnings = await _repository.earnings();
      if (seq != _loadSeq) return;
      _earnings = earnings;
      _error = null;
    } on RidesException catch (e) {
      if (seq == _loadSeq) _error = e.message;
    } finally {
      final list = await payouts;
      if (seq == _loadSeq) {
        if (list != null) {
          _payouts = list;
          _payoutsLoaded = true;
        }
        _isLoading = false;
        _hasLoaded = true;
        _notify();
      }
    }
  }

  /// Re-reads the money unless it was read within the last
  /// [RefreshThrottle.defaultGap] or a read is in flight — for the app
  /// coming back to the foreground on the Earnings tab.
  Future<void> refreshIfStale() async {
    if (_isLoading || !_fetched.isStale) return;
    await load();
  }

  /// The payouts list, or null when it couldn't be read.
  Future<List<Payout>?> _fetchPayouts() async {
    try {
      return await _repository.payouts();
    } on RidesException {
      return null;
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
