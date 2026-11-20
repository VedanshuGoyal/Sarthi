import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../domain/ride.dart';
import 'ride_labels.dart';

/// Display formatting for rides: rupees, times, days, durations, distances.
/// Pure functions of their inputs, so panels and cards stay consistent.
///
/// Words come from [L10n.current], the app's language (English in unit
/// tests). Money keeps "₹" and Indian grouping, and times "9:05 AM", in
/// every language.
abstract final class RideFormat {
  static AppLocalizations get _l10n => L10n.current;

  /// ₹1,23,456 — Indian digit grouping.
  static String rupees(int amount) {
    final negative = amount < 0;
    final digits = amount.abs().toString();
    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final head = digits.substring(0, digits.length - 3);
      final tail = digits.substring(digits.length - 3);
      final pairs = <String>[];
      for (var i = head.length; i > 0; i -= 2) {
        pairs.insert(0, head.substring(i - 2 < 0 ? 0 : i - 2, i));
      }
      grouped = '${pairs.join(',')},$tail';
    }
    return '${negative ? '-' : ''}₹$grouped';
  }

  /// [rupees] of an amount in paise, to the nearest rupee: 5000 → ₹50.
  static String paise(int amount) => rupees((amount / 100).round());

  /// Where a ride's money stands: "Awaiting payment", "Paid · your share
  /// ₹44 after commission", "Paid out". Empty when there's nothing to pay.
  static String payment(Ride ride) =>
      switch ((ride.paymentStatus, ride.sharePaise)) {
        (RidePaymentStatus.paid, final share?) => _l10n.fmtPaidYourShare(
          paise(share),
        ),
        (final status, _) => status.labelIn(_l10n),
      };

  /// "₹50 cancellation fee · Awaiting payment", on a ride the customer
  /// cancelled at the pickup ([Ride.hasCancellationFee]).
  static String cancellationFee(Ride ride) => [
    _l10n.fmtCancellationFee(paise(ride.cancellationFeePaise ?? 0)),
    if (payment(ride).isNotEmpty) payment(ride),
  ].join(' · ');

  /// "Charged ₹200 for the time used (booked ₹340)", on a trip the customer
  /// ended early ([Ride.endedEarly]).
  static String endedEarly(Ride ride) => _l10n.fmtEndedEarlyCharge(
    paise(ride.farePaise),
    paise(ride.bookedFarePaise ?? ride.farePaise),
  );

  /// "₹510 for the time used (booked ₹340)", on a trip that ran past its
  /// booked time ([Ride.ranOverTime]).
  static String ranOver(Ride ride) => _l10n.fmtRanOverCharge(
    paise(ride.farePaise),
    paise(ride.bookedFarePaise ?? ride.farePaise),
  );

  /// 9:05 AM — in every language: drivers read AM/PM as it is.
  static String time(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Today / Tomorrow / Yesterday / Mon, 26 Oct
  static String day(DateTime t, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final diff = _dateOnly(t).difference(today).inDays;
    final l10n = _l10n;
    return switch (diff) {
      0 => l10n.fmtToday,
      1 => l10n.fmtTomorrow,
      -1 => l10n.fmtYesterday,
      _ => l10n.fmtDate(
        l10n.weekdayShort(t.weekday),
        t.day,
        l10n.monthShort(t.month),
      ),
    };
  }

  /// Tomorrow · 9:00 AM
  static String when(DateTime t, {DateTime? now}) =>
      '${day(t, now: now)} · ${time(t)}';

  /// 45 min / 3 h / 1 h 45 min
  static String duration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 60) return _l10n.fmtMinutes(minutes);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? _l10n.fmtHours(h) : _l10n.fmtHoursMinutes(h, m);
  }

  /// 700 m / 7.7 km / 24 km
  static String distance(double meters) {
    if (meters < 1000) return _l10n.fmtMeters((meters / 50).round() * 50);
    final km = meters / 1000;
    return _l10n.fmtKilometers(
      km < 10 ? km.toStringAsFixed(1) : '${km.round()}',
    );
  }

  /// "in 25 min", "in 3 h", "25 min ago" — how far [t] is from [now].
  static String relative(DateTime t, {DateTime? now}) {
    final diff = t.difference(now ?? DateTime.now());
    final label = duration(Duration(minutes: diff.inMinutes.abs()));
    if (diff.inMinutes.abs() < 1) return _l10n.fmtNow;
    if (diff.inHours.abs() >= 24) return day(t, now: now);
    return diff.isNegative ? _l10n.fmtTimeAgo(label) : _l10n.fmtTimeIn(label);
  }

  /// What the ride books the driver for: "3 h hire", "~45 min drive",
  /// "2 stops · 1 h 45 min" — or, for a trip type this build doesn't know,
  /// just the booked span ("2 h").
  static String span(Ride ride) => switch (ride.kind) {
    TripKind.roundTrip => _l10n.fmtSpanHire(
      ride.hours ?? ride.duration.inHours,
    ),
    TripKind.oneWay => _l10n.fmtSpanDrive(
      duration(
        Duration(minutes: ride.estimatedMinutes ?? ride.duration.inMinutes),
      ),
    ),
    TripKind.multiStop => _l10n.fmtSpanStops(
      ride.stops.length,
      duration(ride.duration),
    ),
    TripKind.other => duration(ride.duration),
  };

  /// +91 98765 43210
  static String phone(String e164) {
    if (e164.startsWith('+91') && e164.length == 13) {
      return '+91 ${e164.substring(3, 8)} ${e164.substring(8)}';
    }
    return e164;
  }

  /// "★ 4.9 · 3 ratings" for a customer with ratings, else "New customer".
  static String customerRating(double? average, int count) {
    if (average == null || count == 0) return _l10n.fmtNewCustomer;
    return _l10n.fmtCustomerRating(average.toStringAsFixed(1), count);
  }

  /// "Your rating ★ 4.8 from 12 trips" for the Earnings panel, else
  /// "No ratings yet".
  static String driverRating(EarningsRating? rating) {
    if (rating == null || rating.count == 0) return _l10n.fmtNoRatingsYet;
    return _l10n.fmtDriverRating(
      rating.average.toStringAsFixed(1),
      rating.count,
    );
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// The icon for each trip kind — the same set the customer app's trip
/// chooser uses, so both sides of a booking read alike.
IconData tripKindIcon(TripKind kind) => switch (kind) {
  TripKind.oneWay => Icons.arrow_forward_rounded,
  TripKind.roundTrip => Icons.schedule_rounded,
  TripKind.multiStop => Icons.alt_route_rounded,
  TripKind.other => Icons.directions_car_rounded,
};
