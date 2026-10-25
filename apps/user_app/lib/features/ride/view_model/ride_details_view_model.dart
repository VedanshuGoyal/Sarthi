import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/booking_repository.dart';
import '../domain/driver_location.dart';
import '../domain/my_booking.dart';
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
    ('Completed', b.completedAt, null),
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

/// The ride details screen: one booking from the customer's list, with
/// cancelling, rating the driver, and — in the tracking window — the driver's
/// live location.
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
    DateTime Function()? now,
    DriverLocation? initialLocation,
  }) : _now = now ?? DateTime.now,
       _location = initialLocation,
       _locationChecked = initialLocation != null {
    _booking = _bookings.byId(bookingId);
    _bookings.addListener(_onBookingsChanged);
  }

  final BookingRepository _repository;
  final MyBookingsViewModel _bookings;
  final DateTime Function() _now;
  final String bookingId;
  final Duration pollEvery;

  MyBooking? _booking;
  bool _disposed = false;

  /// The ride as last seen in the list; null only for an id never in it.
  MyBooking? get booking => _booking;

  /// The ride's steps, for the status timeline.
  List<RideMilestone> get timeline =>
      _booking == null ? const [] : rideTimeline(_booking!);

  /// Pull-to-refresh: re-reads the customer's rides, this one included.
  Future<void> refresh() => _bookings.load();

  void _onBookingsChanged() {
    final latest = _bookings.byId(bookingId);
    if (latest == null || identical(latest, _booking)) return;
    final statusChanged = latest.status != _booking?.status;
    _booking = latest;
    // A new stage of the ride may be trackable even if the last wasn't.
    if (statusChanged) _notTracking = false;
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

  bool get isCancelling => _isCancelling;

  /// Why the last cancel failed, safe to show.
  String? get cancelError => _cancelError;

  /// Cancels the ride with the customer's [reason]; true once it's cancelled.
  /// On success the list holds the cancelled ride and reloads.
  Future<bool> cancel({String? reason}) async {
    final b = _booking;
    if (b == null || !b.canCancel || _isCancelling) return false;
    _isCancelling = true;
    _cancelError = null;
    _notify();
    try {
      _bookings.applyUpdate(await _repository.cancel(b.id, reason: reason));
      unawaited(_bookings.load());
      return true;
    } on BookingActionException catch (e) {
      _cancelError = switch (e.code) {
        BookingErrorCode.wrongState =>
          'This ride has already started or finished, so it can no longer '
              'be cancelled.',
        BookingErrorCode.notFound => "We couldn't find this ride any more.",
        _ => e.message,
      };
      // The ride moved on without us; show where it is now.
      if (e.code == BookingErrorCode.wrongState) unawaited(_bookings.load());
      return false;
    } finally {
      _isCancelling = false;
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
