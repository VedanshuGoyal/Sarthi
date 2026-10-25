import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/booking_repository.dart';
import '../domain/my_booking.dart';

/// The customer's bookings, for the Activity tab: who is driving, where
/// they are in the trip, the start code to share, and the finished trips.
///
/// While the signed-in shell is up it refreshes every [pollEvery] — often
/// enough that "Driver assigned" and the start code appear without the
/// customer pulling to refresh (pushes refresh it sooner).
///
/// It also decides when to ask for a rating ([ratingPrompt]): for a ride that
/// finishes while the app is open, or — on opening the app — the latest
/// finished ride if it ended within [ratingPromptWindow] and is unrated. Each
/// ride is asked about at most once per session.
class MyBookingsViewModel extends ChangeNotifier {
  /// [initialBookings] seeds the list as if already loaded, and [now] is the
  /// clock the rating prompt measures against — seams for previews and tests.
  MyBookingsViewModel({
    required this._repository,
    this.pollEvery = const Duration(seconds: 30),
    List<MyBooking>? initialBookings,
    DateTime Function()? now,
  }) : _bookings = initialBookings ?? const [],
       _hasLoaded = initialBookings != null,
       _now = now ?? DateTime.now;

  final BookingRepository _repository;
  final Duration pollEvery;
  final DateTime Function() _now;

  /// How recently a ride must have finished for opening the app to ask about
  /// it.
  static const Duration ratingPromptWindow = Duration(hours: 24);

  List<MyBooking> _bookings;
  bool _hasLoaded;
  String? _error;
  Timer? _timer;
  bool _disposed = false;
  Future<void>? _loading;

  /// Rides changed on this phone (cancelled, rated) while a load was in
  /// flight; they win over that load's possibly older copy.
  final Map<String, MyBooking> _localEdits = {};

  /// Rides seen finishing while the app was open.
  final Set<String> _finishedThisSession = {};

  /// Rides already asked about this session — rated or waved away.
  final Set<String> _ratingAsked = {};

  /// Unfinished bookings, soonest first.
  List<MyBooking> get active =>
      _bookings.where((b) => b.status.isActive).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Finished bookings — completed or cancelled — latest first.
  List<MyBooking> get past =>
      _bookings.where((b) => !b.status.isActive).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  bool get isLoading => _loading != null;

  /// Whether a load has finished at least once — until then an empty list
  /// means "not fetched yet", not "no rides".
  bool get hasLoaded => _hasLoaded;

  /// The last load failure, safe to show.
  String? get error => _error;

  /// The booking with [id], if it's in the list.
  MyBooking? byId(String id) {
    for (final booking in _bookings) {
      if (booking.id == id) return booking;
    }
    return null;
  }

  /// The ride to ask the customer to rate now, or null. Asking is the shell's
  /// job; it calls [markRatingAsked] as it does, so each ride is asked once.
  MyBooking? get ratingPrompt {
    final finished =
        _bookings.where((b) => b.status == BookingStatus.completed).toList()
          ..sort((a, b) => _finishedAt(b).compareTo(_finishedAt(a)));
    bool unasked(MyBooking b) => b.canRate && !_ratingAsked.contains(b.id);
    // A ride that finished while the app was open.
    for (final booking in finished) {
      if (_finishedThisSession.contains(booking.id) && unasked(booking)) {
        return booking;
      }
    }
    // Otherwise the latest finished ride, if it's recent and still unrated.
    final latest = finished.firstOrNull;
    if (latest != null &&
        unasked(latest) &&
        _now().difference(_finishedAt(latest)) <= ratingPromptWindow) {
      return latest;
    }
    return null;
  }

  /// Records that the customer was asked to rate [id], so they aren't asked
  /// again this session whether they rate it or not.
  void markRatingAsked(String id) {
    if (_ratingAsked.add(id)) _notify();
  }

  static DateTime _finishedAt(MyBooking b) =>
      b.completedAt ?? b.endsAt ?? b.scheduledAt;

  /// Fetches the list. A call while a load is running waits for that one.
  Future<void> load() {
    if (_loading case final running?) return running;
    final loading = _loading = _load();
    _notify();
    return loading;
  }

  Future<void> _load() async {
    try {
      final fetched = await _repository.myBookings();
      final previous = {for (final b in _bookings) b.id: b.status};
      _bookings = [for (final b in fetched) _localEdits[b.id] ?? b];
      if (_hasLoaded) {
        for (final b in _bookings) {
          if (b.status == BookingStatus.completed &&
              (previous[b.id]?.isActive ?? false)) {
            _finishedThisSession.add(b.id);
          }
        }
      }
      _error = null;
    } on BookingSubmitException catch (e) {
      _error = e.message;
    } finally {
      _localEdits.clear();
      _hasLoaded = true;
      _loading = null;
      _notify();
    }
  }

  /// Puts the server's latest copy of one booking — returned by a cancel or
  /// rating — into the list straight away, without waiting for a reload.
  void applyUpdate(MyBooking booking) {
    final index = _bookings.indexWhere((b) => b.id == booking.id);
    if (index < 0) return;
    _bookings = [..._bookings]..[index] = booking;
    if (_loading != null) _localEdits[booking.id] = booking;
    _notify();
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
