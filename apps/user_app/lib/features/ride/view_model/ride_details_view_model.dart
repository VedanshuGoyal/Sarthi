import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show ImageProvider;

import '../data/booking_repository.dart';
import '../data/upi_checkout.dart';
import '../domain/driver_location.dart';
import '../domain/my_booking.dart';
import '../domain/payment_checkout.dart';
import 'my_bookings_view_model.dart';

/// How far one step of a ride's timeline has got.
enum MilestoneState {
  /// Happened.
  done,

  /// The step the ride is at now.
  current,

  /// Still to come.
  upcoming,

  /// Where the ride ended early — cancelled, or no driver took it.
  ended,
}

/// One step of a ride's timeline: "Driver assigned · 9:12 AM".
@immutable
class RideMilestone {
  const RideMilestone({
    required this.label,
    required this.state,
    this.at,
    this.detail,
  });

  final String label;
  final MilestoneState state;

  /// When it happened, if it has and the server said.
  final DateTime? at;

  /// A second line — the driver's name, the cancel reason.
  final String? detail;
}

/// A ride's steps from booking to completion — or to where it ended early.
List<RideMilestone> rideTimeline(MyBooking b) {
  final steps = <(String, DateTime?, String?)>[
    ('Booked', b.createdAt, null),
    ('Driver assigned', b.acceptedAt, b.driverName),
    ('Driver arrived', b.arrivedAt, null),
    ('Trip started', b.startedAt, null),
    (b.endedEarly ? 'Ended early' : 'Completed', b.completedAt, null),
  ];
  // How many steps in the ride got, counting from Booked.
  final reached = switch (b.status) {
    BookingStatus.requested || BookingStatus.expired => 0,
    BookingStatus.accepted => 1,
    BookingStatus.arrived => 2,
    BookingStatus.inProgress => 3,
    BookingStatus.completed => 4,
    // A ride can only be cancelled before it starts.
    BookingStatus.cancelled =>
      b.arrivedAt != null
          ? 2
          : b.acceptedAt != null
          ? 1
          : 0,
  };
  final endedEarly =
      b.status == BookingStatus.cancelled || b.status == BookingStatus.expired;
  final finished = endedEarly || b.status == BookingStatus.completed;
  return [
    for (final (i, (label, at, detail)) in steps.indexed)
      if (!endedEarly || i <= reached)
        RideMilestone(
          label: label,
          at: i <= reached ? at : null,
          detail: i <= reached ? detail : null,
          state: i < reached || (i == reached && finished)
              ? MilestoneState.done
              : i == reached
              ? MilestoneState.current
              : MilestoneState.upcoming,
        ),
    if (b.status == BookingStatus.cancelled)
      RideMilestone(
        label: b.cancelledByLabel ?? 'Cancelled',
        at: b.cancelledAt,
        detail: b.cancelReason,
        state: MilestoneState.ended,
      ),
    if (b.status == BookingStatus.expired)
      const RideMilestone(
        label: 'No driver found',
        detail: 'No driver accepted in time.',
        state: MilestoneState.ended,
      ),
  ];
}

/// How a cancel attempt ended.
enum CancelOutcome {
  /// The ride is cancelled — with its fee due, if it had one.
  cancelled,

  /// It wasn't; [RideDetailsViewModel.cancelError] says why.
  failed,

  /// Nothing changed: cancelling now costs more than the customer was
  /// shown (the driver reached the pickup meanwhile). Ask again, showing
  /// [RideDetailsViewModel.cancelFeePaise].
  feeChanged,
}

/// The ride details screen: one booking from the customer's list, with
/// cancelling, ending the trip early, paying for it (or its cancellation
/// fee) by UPI, rating the driver, and — in the tracking window — the
/// driver's live location.
///
/// The booking itself comes from [MyBookingsViewModel], so the screen moves
/// along with every list refresh; a cancel or rating puts the server's reply
/// straight into that list and reloads it. The location is polled every
/// [pollEvery] only while the screen says it's visible ([startTracking] /
/// [stopTracking]) and the ride is in the window, and stops for good once the
/// server says it isn't sharing (`not_tracking`) — until the ride's status
/// changes.
class RideDetailsViewModel extends ChangeNotifier {
  /// [now] is the clock the tracking window and "updated 10 s ago" read, and
  /// [initialLocation] seeds a driver fix — seams for previews and tests.
  RideDetailsViewModel({
    required this._repository,
    required this._bookings,
    required this.bookingId,
    this.pollEvery = const Duration(seconds: 5),
    this.paySyncEvery = const Duration(seconds: 2),
    this._checkout,
    this.flowId = 'mojud',
    DateTime Function()? now,
    DriverLocation? initialLocation,
  }) : _now = now ?? DateTime.now,
       _location = initialLocation,
       _locationChecked = initialLocation != null {
    _booking = _bookings.byId(bookingId);
    _confirming = _bookings.isConfirmingPayment(bookingId);
    _bookings.addListener(_onBookingsChanged);
    // Opening a ride that's due: it may have been paid while the app was
    // away (Android can kill it behind the UPI app before it hears back).
    if ((_booking?.canPay ?? false) && _checkout != null && !_confirming) {
      _openCheck = _syncPayment(bookingId, attempts: 1);
    }
  }

  final BookingRepository _repository;
  final MyBookingsViewModel _bookings;
  final DateTime Function() _now;
  final String bookingId;
  final Duration pollEvery;

  /// How long to wait between asking the server whether a payment that
  /// just went through has landed.
  final Duration paySyncEvery;

  /// The payment page; null where paying isn't possible (previews).
  final UpiCheckout? _checkout;

  /// Ties the payment SDK's logs to this customer.
  final String flowId;

  MyBooking? _booking;
  bool _disposed = false;

  /// The ride as last seen in the list; null only for an id never in it.
  MyBooking? get booking => _booking;

  /// The driver's photo, or null when there's no driver or no photo.
  ImageProvider? get driverPhoto {
    final b = _booking;
    final version = b?.driverPhotoVersion;
    return b == null || version == null
        ? null
        : _repository.driverPhoto(b.id, version);
  }

  /// The ride's steps, for the status timeline.
  List<RideMilestone> get timeline =>
      _booking == null ? const [] : rideTimeline(_booking!);

  /// Pull-to-refresh: re-reads the customer's rides, this one included.
  Future<void> refresh() => _bookings.load();

  void _onBookingsChanged() {
    final latest = _bookings.byId(bookingId);
    final confirming = _bookings.isConfirmingPayment(bookingId);
    final confirmingChanged = confirming != _confirming;
    _confirming = confirming;
    if (latest == null || identical(latest, _booking)) {
      if (confirmingChanged) _notify();
      return;
    }
    final statusChanged = latest.status != _booking?.status;
    _booking = latest;
    if (!latest.canCancel) _quotedFeePaise = null;
    // A new stage of the ride may be trackable even if the last wasn't.
    if (statusChanged) _notTracking = false;
    if (latest.paymentStatus == RidePaymentStatus.paid) _payError = null;
    _syncPolling();
    _notify();
  }

  // --- Live tracking ---------------------------------------------------------

  Timer? _timer;
  bool _visible = false;
  bool _notTracking = false;
  bool _fetching = false;
  DriverLocation? _location;
  bool _locationChecked;

  /// Whether the driver's location should be on screen now: the ride is in
  /// the tracking window and the server hasn't said otherwise.
  bool get isTracking =>
      !_notTracking && (_booking?.isInTrackingWindow(_now()) ?? false);

  /// Whether the location is being polled (the screen is visible, a driver is
  /// on the ride, and the server hasn't refused).
  bool get isPolling => _timer != null;

  /// The driver's latest fix; null until one arrives, or when they haven't
  /// shared one lately.
  DriverLocation? get driverLocation => _location;

  /// Straight-line distance from the driver to the pickup, in metres.
  double? get driverDistanceMetres {
    final pickup = _booking?.pickupPoint;
    final location = _location;
    if (pickup == null || location == null) return null;
    return location.point.distanceTo(pickup);
  }

  /// One line under the map: "Ravi is 2.3 km away · updated 10 s ago".
  String get trackingLine {
    final b = _booking;
    final location = _location;
    if (b == null || location == null) {
      return _locationChecked
          ? "Waiting for your driver's location"
          : "Finding your driver's location…";
    }
    final name = b.driverFirstName ?? 'Your driver';
    final metres = driverDistanceMetres;
    final String where;
    if (b.status == BookingStatus.inProgress) {
      where = '$name is on your trip';
    } else if (metres == null) {
      where = "$name's location";
    } else if (b.status == BookingStatus.arrived && metres < 100) {
      where = '$name is at your pickup';
    } else {
      where = '$name is ${formatDistance(metres)} away';
    }
    final age = formatAge(_now().difference(location.updatedAt));
    return '$where · updated $age';
  }

  /// "350 m", "2.3 km", "14 km".
  static String formatDistance(double metres) {
    if (metres < 1000) return '${(metres / 10).round() * 10} m';
    final km = metres / 1000;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  /// "just now", "10 s ago", "3 min ago", "2 h ago".
  static String formatAge(Duration age) {
    if (age.inSeconds < 5) return 'just now';
    if (age.inMinutes < 1) return '${age.inSeconds} s ago';
    if (age.inHours < 1) return '${age.inMinutes} min ago';
    return '${age.inHours} h ago';
  }

  /// The screen is showing: poll while the ride allows it.
  void startTracking() {
    _visible = true;
    _syncPolling();
  }

  /// The screen is hidden or gone: stop polling.
  void stopTracking() {
    _visible = false;
    _syncPolling();
  }

  /// Runs the poll timer exactly while it's useful: the screen is visible,
  /// a driver is on the ride, and the server hasn't refused. Each tick checks
  /// the window itself, so an accepted ride starts sharing an hour before
  /// its start without the screen being reopened.
  void _syncPolling() {
    final status = _booking?.status;
    final wanted =
        _visible &&
        !_notTracking &&
        (status == BookingStatus.accepted ||
            status == BookingStatus.arrived ||
            status == BookingStatus.inProgress);
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null) {
      _timer = Timer.periodic(pollEvery, (_) => _tick());
      _tick();
    }
  }

  void _tick() {
    if (isTracking) {
      _fetchLocation();
    } else {
      // Nothing to fetch yet; keep "updated … ago" and the window current.
      _notify();
    }
  }

  Future<void> _fetchLocation() async {
    if (_fetching) return;
    _fetching = true;
    try {
      _location = await _repository.driverLocation(bookingId);
      _locationChecked = true;
    } on BookingActionException catch (e) {
      if (e.code == BookingErrorCode.notTracking ||
          e.code == BookingErrorCode.notFound) {
        _notTracking = true;
        _location = null;
        _syncPolling();
      }
      // Anything else is a blip; the next tick tries again.
    } finally {
      _fetching = false;
      _notify();
    }
  }

  // --- Cancelling ------------------------------------------------------------

  bool _isCancelling = false;
  String? _cancelError;

  /// The fee the server said cancelling costs when it refused a cancel for
  /// less — in case the list hasn't caught up with the driver's arrival.
  int? _quotedFeePaise;

  bool get isCancelling => _isCancelling;

  /// Why the last cancel failed, safe to show.
  String? get cancelError => _cancelError;

  /// What cancelling now costs, in paise; 0 while it's free. The
  /// confirmation shows it, and the view sends what it showed to [cancel].
  int get cancelFeePaise {
    final b = _booking;
    if (b == null || !b.canCancel) return 0;
    return max(b.cancelFeeNowPaise, _quotedFeePaise ?? 0);
  }

  /// Cancels the ride with the customer's [reason], agreeing to pay at most
  /// [acceptFeePaise] — the fee the confirmation showed them. On success the
  /// list holds the cancelled ride and reloads.
  ///
  /// When cancelling costs more than that by now (the driver just reached
  /// the pickup), nothing is cancelled: the list is refreshed and the
  /// outcome is [CancelOutcome.feeChanged], so the view asks again with
  /// [cancelFeePaise]. A fee is never taken that the customer didn't see.
  Future<CancelOutcome> cancel({
    String? reason,
    required int acceptFeePaise,
  }) async {
    final b = _booking;
    if (b == null || !b.canCancel || _isCancelling) {
      return CancelOutcome.failed;
    }
    _isCancelling = true;
    _cancelError = null;
    _notify();
    try {
      _bookings.applyUpdate(
        await _repository.cancel(
          b.id,
          reason: reason,
          acceptFeePaise: acceptFeePaise,
        ),
      );
      _quotedFeePaise = null;
      unawaited(_bookings.load());
      return CancelOutcome.cancelled;
    } on BookingActionException catch (e) {
      if (e.code == BookingErrorCode.cancellationFee) {
        if (e.feePaise case final fee?) _quotedFeePaise = fee;
        // Show where the ride is now (the driver at the pickup) when asking
        // again.
        await _bookings.load();
        if (cancelFeePaise > acceptFeePaise) return CancelOutcome.feeChanged;
        // Refused for a fee neither the server nor the list names: don't
        // offer the same free cancel again.
        _cancelError =
            'Cancelling now has a fee. Pull down to refresh, then try again.';
        return CancelOutcome.failed;
      }
      _cancelError = switch (e.code) {
        BookingErrorCode.wrongState =>
          'This ride has already started or finished, so it can no longer '
              'be cancelled.',
        BookingErrorCode.notFound => "We couldn't find this ride any more.",
        _ => e.message,
      };
      // The ride moved on without us; show where it is now.
      if (e.code == BookingErrorCode.wrongState) unawaited(_bookings.load());
      return CancelOutcome.failed;
    } finally {
      _isCancelling = false;
      _notify();
    }
  }

  // --- Ending the trip early -------------------------------------------------

  bool _isEnding = false;
  String? _endError;

  bool get isEndingTrip => _isEnding;

  /// Why the last "End trip now" failed, safe to show.
  String? get endTripError => _endError;

  /// Whether "End trip now" should be offered: the trip is in progress.
  bool get canEndTrip => _booking?.canEndTrip ?? false;

  /// Ends the trip now; true once it's ended. The customer then pays by the
  /// hour for the time used, never more than the booked fare: the list
  /// holds the completed ride, due for payment, and reloads.
  Future<bool> endTrip() async {
    final b = _booking;
    if (b == null || !b.canEndTrip || _isEnding) return false;
    _isEnding = true;
    _endError = null;
    _notify();
    try {
      _bookings.applyUpdate(await _repository.endTrip(b.id));
      unawaited(_bookings.load());
      return true;
    } on BookingActionException catch (e) {
      final movedOn =
          e.code == BookingErrorCode.cannotEnd ||
          e.code == BookingErrorCode.wrongState;
      _endError = switch (e.code) {
        _ when movedOn => "This trip isn't in progress any more.",
        BookingErrorCode.notFound => "We couldn't find this ride any more.",
        _ => e.message,
      };
      // The driver may have ended it already; show where it is now.
      if (movedOn) unawaited(_bookings.load());
      return false;
    } finally {
      _isEnding = false;
      _notify();
    }
  }

  // --- Rating ----------------------------------------------------------------

  int _stars = 0;
  String _note = '';
  bool _isRating = false;
  String? _ratingError;

  /// The stars picked so far, 0 for none.
  int get ratingStars => _stars;
  String get ratingNote => _note;
  bool get isSubmittingRating => _isRating;

  /// Why the last rating failed, safe to show.
  String? get ratingError => _ratingError;

  bool get canSubmitRating =>
      (_booking?.canRate ?? false) && _stars >= 1 && _stars <= 5 && !_isRating;

  void setRatingStars(int stars) {
    _stars = stars.clamp(1, 5);
    _ratingError = null;
    _notify();
  }

  void setRatingNote(String note) {
    _note = note;
    if (_ratingError != null) {
      _ratingError = null;
      _notify();
    }
  }

  /// Sends the stars and note; true once the rating is saved. On success the
  /// list holds the rated ride and reloads.
  Future<bool> submitRating() async {
    final b = _booking;
    if (b == null || !canSubmitRating) return false;
    _isRating = true;
    _ratingError = null;
    _notify();
    try {
      _bookings.applyUpdate(
        await _repository.rate(b.id, _stars, note: _note.trim()),
      );
      unawaited(_bookings.load());
      return true;
    } on BookingActionException catch (e) {
      _ratingError = switch (e.code) {
        BookingErrorCode.wrongState => 'This ride has already been rated.',
        BookingErrorCode.invalidRating =>
          'Pick 1 to 5 stars, and keep the note under $maxRatingNoteLength '
              'characters.',
        BookingErrorCode.notFound => "We couldn't find this ride any more.",
        _ => e.message,
      };
      if (e.code == BookingErrorCode.wrongState) unawaited(_bookings.load());
      return false;
    } finally {
      _isRating = false;
      _notify();
    }
  }

  // --- Paying ----------------------------------------------------------------

  bool _isPaying = false;
  String? _payError;

  /// Whether the list is still confirming a payment the UPI app said went
  /// through (see [MyBookingsViewModel.confirmPayment]).
  bool _confirming = false;

  /// The check made on opening a due ride; [pay] waits for it.
  Future<MyBooking?>? _openCheck;

  static const String _stillConfirming =
      "We're still confirming your payment with the bank. This ride will "
      'show as paid in a minute or two.';

  bool get isPaying => _isPaying;

  /// Why the last payment didn't complete, safe to show — or, while a
  /// payment is being confirmed, that it is.
  String? get payError => _payError ?? (_confirming ? _stillConfirming : null);

  /// Whether the pay button should work: the ride is due, the app can open
  /// the payment page, and no payment that went through is still being
  /// confirmed — paying again then could take the money twice.
  bool get canPay =>
      (_booking?.canPay ?? false) && _checkout != null && !_confirming;

  /// Opens the UPI payment page for the completed ride (or the cancelled
  /// ride's fee — the server sets the amount), then has the server check
  /// with the gateway; true once it's paid. Whatever the page says when it
  /// closes, only the server's check counts.
  Future<bool> pay() async {
    var b = _booking;
    final checkout = _checkout;
    if (b == null || checkout == null || !canPay || _isPaying) return false;
    _isPaying = true;
    _payError = null;
    _notify();
    try {
      // The open check may have found it paid: never start a second order.
      if (_openCheck case final check?) {
        _openCheck = null;
        await check;
        if (_disposed) return false;
        b = _booking ?? b;
        if (!b.canPay) return b.paymentStatus == RidePaymentStatus.paid;
      }
      final PaymentCheckout order;
      try {
        order = await _repository.startPayment(b.id);
      } on BookingActionException catch (e) {
        if (e.code != BookingErrorCode.alreadyPaid) rethrow;
        // Paid from an earlier attempt: show it.
        await _syncPayment(b.id, attempts: 1);
        return true;
      }
      // The customer backed out while the order was being made: don't throw
      // a payment page up over wherever they went instead.
      if (_disposed) return false;
      final outcome = await checkout.open(order, flowId: flowId);
      final latest = await _syncPayment(
        b.id,
        attempts: outcome == CheckoutOutcome.success ? 5 : 1,
      );
      if (latest?.paymentStatus == RidePaymentStatus.paid) return true;
      // The UPI app says it went through: keep checking, with Pay off.
      if (outcome == CheckoutOutcome.success) {
        unawaited(_bookings.confirmPayment(b.id));
      }
      _payError = switch (outcome) {
        CheckoutOutcome.success => _stillConfirming,
        CheckoutOutcome.failure =>
          "The payment didn't go through. Please try again.",
        CheckoutOutcome.interrupted => 'Payment cancelled.',
      };
      return false;
    } on BookingActionException catch (e) {
      _payError = switch (e.code) {
        BookingErrorCode.paymentsOff =>
          "Paying in the app isn't available yet.",
        BookingErrorCode.wrongState => "This ride can't be paid for yet.",
        BookingErrorCode.notFound => "We couldn't find this ride any more.",
        _ => e.message,
      };
      return false;
    } on UpiCheckoutException catch (e) {
      _payError = e.message;
      return false;
    } finally {
      _isPaying = false;
      _notify();
    }
  }

  /// Asks the server to re-check the payment up to [attempts] times,
  /// [paySyncEvery] apart, until it's paid; puts each reply in the list.
  ///
  /// Keeps going if the customer leaves the screen meanwhile: the payment
  /// has already gone through at the gateway, and until the server has
  /// checked, the Activity list (which outlives this screen) offers "Pay"
  /// for it again.
  Future<MyBooking?> _syncPayment(String id, {required int attempts}) async {
    MyBooking? latest;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(paySyncEvery);
      try {
        latest = await _repository.syncPayment(id);
        _bookings.applyUpdate(latest);
      } on BookingActionException {
        // A blip; the next attempt (or the list's own refresh) catches up.
      }
      if (latest?.paymentStatus == RidePaymentStatus.paid) break;
    }
    return latest;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _bookings.removeListener(_onBookingsChanged);
    super.dispose();
  }
}
