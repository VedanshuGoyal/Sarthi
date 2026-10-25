import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/booking_repository.dart';
import '../domain/my_booking.dart';

/// The customer's bookings, for the Activity tab: who is driving, where
/// they are in the trip, the start code to share, and the finished trips.
///
/// There is no push channel yet, so while the signed-in shell is up it
/// refreshes every [pollEvery] — often enough that "Driver assigned" and the
/// start code appear without the customer pulling to refresh.
class MyBookingsViewModel extends ChangeNotifier {
  MyBookingsViewModel({
    required this._repository,
    this.pollEvery = const Duration(seconds: 30),
  });

  final BookingRepository _repository;
  final Duration pollEvery;

  List<MyBooking> _bookings = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;
  Timer? _timer;
  bool _disposed = false;

  /// Unfinished bookings, soonest first.
  List<MyBooking> get active =>
      _bookings.where((b) => b.status.isActive).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Finished bookings — completed or cancelled — latest first.
  List<MyBooking> get past =>
      _bookings.where((b) => !b.status.isActive).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  bool get isLoading => _isLoading;

  /// Whether a load has finished at least once — until then an empty list
  /// means "not fetched yet", not "no rides".
  bool get hasLoaded => _hasLoaded;

  /// The last load failure, safe to show.
  String? get error => _error;

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _notify();
    try {
      _bookings = await _repository.myBookings();
      _error = null;
    } on BookingSubmitException catch (e) {
      _error = e.message;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      _notify();
    }
  }

  /// Loads now and keeps refreshing until [stopPolling].
  void startPolling() {
    load();
    _timer ??= Timer.periodic(pollEvery, (_) => load());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
