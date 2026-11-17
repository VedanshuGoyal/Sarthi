import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show ImageProvider;

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
///
/// It also says what the customer owes on other bookings ([carriedWith],
/// [owed]): an unpaid ride or fee doesn't stop them booking, it's added to
/// their next payment.
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

  /// The photo of [booking]'s driver, or null when it has none to show.
  ImageProvider? driverPhoto(MyBooking booking) {
    final version = booking.driverPhotoVersion;
    return version == null
        ? null
        : _repository.driverPhoto(booking.id, version);
  }

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

  /// Fetches the list afresh: waits for a load already running — it may
  /// have been sent before a change the server just made — then loads again.
  /// Used after a payment, which can mark other bookings paid too.
  Future<void> reload() async {
    if (_loading case final running?) await running;
    return load();
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

  // --- Money owed on other bookings -----------------------------------------

  /// What paying for [booking] also collects for the customer's other
  /// bookings (the server's `carriedPaise`), or null when nothing.
  EarlierDues? carriedWith(MyBooking booking) {
    final paise = booking.carriedPaise;
    if (paise <= 0) return null;
    return (paise: paise, oneRide: _owedByOneRide(paise, besides: booking.id));
  }

  /// What the customer owes, as far as the list shows — what will be added
  /// to the payment of a ride they book now — or null when nothing. The
  /// most any one booking says (a due ride's own charge plus what it
  /// carries, an active one's carried amount), or the due rides' charges
  /// added up if that's more (servers that don't carry dues).
  EarlierDues? get owed {
    var most = 0;
    var dueTotal = 0;
    for (final b in _bookings) {
      if (b.canPay) {
        dueTotal += b.chargePaise;
        most = max(most, b.totalDuePaise);
      } else if (b.status.isActive) {
        most = max(most, b.carriedPaise);
      }
    }
    final paise = max(most, dueTotal);
    return paise <= 0 ? null : (paise: paise, oneRide: _owedByOneRide(paise));
  }

  /// Whether [paise] owed is all one ride's: the list shows exactly one due
  /// booking (other than [besides]), for exactly that amount.
  bool _owedByOneRide(int paise, {String? besides}) {
    final due = [
      for (final b in _bookings)
        if (b.canPay && b.id != besides) b,
    ];
    return due.length == 1 && due.single.chargePaise == paise;
  }

  // --- Payments the UPI app said went through --------------------------------

  /// Rides being re-checked by [confirmPayment], by id.
  final Map<String, Future<void>> _confirming = {};

  /// Whether a payment covering ride [id] went through in the UPI app but
  /// the server hasn't confirmed it yet: ride [id]'s own, or another ride's
  /// that also collected what's owed on others. Paying again meanwhile
  /// could take the money twice, so the ride's Pay button stays off. Lives
  /// here, not on the ride screen, so leaving and reopening the ride doesn't
  /// turn Pay back on.
  bool isConfirmingPayment(String id) {
    if (_confirming.containsKey(id)) return true;
    if (_confirming.isEmpty) return false;
    bool carries(String rideId) => (byId(rideId)?.carriedPaise ?? 0) > 0;
    return carries(id) || _confirming.keys.any(carries);
  }

  /// Keeps asking the server to check ride [id]'s payment with the gateway,
  /// waiting [first] and then twice as long each time up to [longest], until
  /// it's paid, [giveUpAfter] has passed (the server's own sweep and the
  /// list refresh carry on), or this view model is gone. One run per ride.
  /// Once it's paid the list is reloaded: the payment may have cleared the
  /// customer's other bookings too.
  Future<void> confirmPayment(
    String id, {
    Duration first = const Duration(seconds: 5),
    Duration longest = const Duration(seconds: 30),
    Duration giveUpAfter = const Duration(minutes: 10),
  }) {
    if (_confirming[id] case final running?) return running;
    final run = _confirmLoop(id, first, longest, giveUpAfter).whenComplete(() {
      _confirming.remove(id);
      _notify();
    });
    _confirming[id] = run;
    _notify();
    return run;
  }

  Future<void> _confirmLoop(
    String id,
    Duration first,
    Duration longest,
    Duration giveUpAfter,
  ) async {
    var wait = first;
    var waited = Duration.zero;
    while (waited < giveUpAfter) {
      await Future<void>.delayed(wait);
      waited += wait;
      if (_disposed) return;
      // A list refresh may have seen it land already.
      if (byId(id)?.paymentStatus != RidePaymentStatus.due) return;
      try {
        final latest = await _repository.syncPayment(id);
        applyUpdate(latest);
        if (latest.paymentStatus == RidePaymentStatus.paid) {
          await reload();
          return;
        }
        if (latest.paymentStatus != RidePaymentStatus.due) return;
      } on BookingActionException {
        // A blip; try again after the next wait.
      }
      wait = wait * 2 > longest ? longest : wait * 2;
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
