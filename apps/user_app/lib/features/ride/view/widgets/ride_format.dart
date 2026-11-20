import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/my_booking.dart';
import '../../domain/trip_type.dart';
import '../../ride_labels.dart';

/// How the ride cards and the ride details screen word a booking — shared so
/// a ride reads the same in the list and on its own screen.
///
/// Words come from the app's language: `context.l10n` where a context is
/// passed, else [L10n.current] (English in unit tests). Amounts keep "₹",
/// and times read "9:30 AM", in every language.
abstract final class RideFormat {
  static AppLocalizations get _l10n => L10n.current;

  static IconData tripIcon(TripType type) => switch (type) {
    TripType.oneWay => Icons.arrow_forward_rounded,
    TripType.roundTrip => Icons.schedule_rounded,
    TripType.multiStop => Icons.alt_route_rounded,
  };

  /// "One-Way", "Round Trip", "Multi-Stop".
  static String tripLabel(TripType type) => type.labelIn(_l10n);

  /// "Today, 9:30 AM", "Tomorrow, …", or "Mon, Oct 26, …" further out.
  static String when(BuildContext context, DateTime at) {
    final l10n = context.l10n;
    return l10n.fmtDayAndTime(day(l10n, at), time(context, at));
  }

  /// "Today", "Tomorrow", "Yesterday", or "Mon, Oct 26" further out.
  static String day(AppLocalizations l10n, DateTime at, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final days = DateTime(
      at.year,
      at.month,
      at.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    return switch (days) {
      -1 => l10n.fmtYesterday,
      0 => l10n.fmtToday,
      1 => l10n.fmtTomorrow,
      _ => date(l10n, at),
    };
  }

  /// "Mon, Oct 26" — "सोम, 26 अक्टूबर" in Hindi.
  static String date(AppLocalizations l10n, DateTime at) => l10n.fmtDate(
    l10n.weekdayShort(at.weekday),
    at.day,
    l10n.monthShort(at.month),
  );

  /// "9:30 AM" — in every language, as the customer reads the clock.
  static String time(BuildContext context, DateTime at) => clock(at);

  /// [time] without a context: "9:30 AM", "12:05 PM".
  static String clock(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "₹196", or "≈ ₹196" while the fare is an estimate.
  static String fare(MyBooking b) =>
      b.fareEstimated ? '≈ ₹${b.fareRupees}' : '₹${b.fareRupees}';

  /// An amount in paise in whole rupees, the way fares read: "₹50".
  static String rupees(int paise) => '₹${(paise / 100).round()}';

  /// "Charged ₹320 for the time used (booked ₹640).", for a trip the
  /// customer ended early; null for any other.
  static String? endedEarly(MyBooking b) {
    final booked = b.bookedFarePaise;
    if (!b.endedEarly || booked == null) return null;
    return _l10n.fmtEndedEarly(rupees(b.farePaise), rupees(booked));
  }

  /// "Ran past the booked time. Charged ₹960 for 4 h (booked ₹640).", for
  /// a trip that went over its booked hours; null for any other.
  static String? ranOver(MyBooking b) {
    final booked = b.bookedFarePaise;
    if (!b.ranOver || booked == null) return null;
    final hours = b.hoursUsed;
    return hours == null
        ? _l10n.fmtRanOver(rupees(b.farePaise), rupees(booked))
        : _l10n.fmtRanOverHours(rupees(b.farePaise), hours, rupees(booked));
  }

  /// The ride screen's note while a trip is past its booked time.
  static String get pastBookedTime => _l10n.fmtPastBookedTime;

  /// "₹50 unpaid from an earlier ride will be added when you pay for this
  /// trip.": on an upcoming or ongoing ride — or one about to be booked —
  /// while the customer owes on earlier ones.
  static String carriedNote(EarlierDues dues) =>
      _l10n.fmtCarriedNote(rupees(dues.paise), dues.oneRide ? 'one' : 'other');

  /// "Includes ₹50 from another ride.", by the Pay button of a ride whose
  /// payment also clears what's owed on the customer's other bookings.
  static String carriedIncluded(EarlierDues dues) => _l10n.fmtCarriedIncluded(
    rupees(dues.paise),
    dues.oneRide ? 'one' : 'other',
  );

  /// "Paid ₹690 together with 1 other ride.", on the receipt of a booking
  /// whose payment also paid others of the customer's; null when it paid
  /// this booking alone. Rides and cancellation fees are counted apart, and
  /// "other" only names the same kind as this booking.
  static String? paidTogether(MyBooking b) {
    final others = b.paidTogetherWith;
    final payment = b.payment;
    if (others.isEmpty || payment == null) return null;
    final l10n = _l10n;
    final rides = others
        .where((line) => line.kind == PaymentLineKind.ride)
        .length;
    final fees = others.length - rides;
    final thisIsFee = b.hasCancellationFee;
    final parts = [
      if (rides > 0)
        thisIsFee ? l10n.fmtRideCount(rides) : l10n.fmtOtherRides(rides),
      if (fees > 0)
        thisIsFee
            ? l10n.fmtOtherCancellationFees(fees)
            : l10n.fmtCancellationFeeCount(fees),
    ];
    return l10n.fmtPaidTogether(
      rupees(payment.paidPaise),
      parts.length == 2 ? l10n.fmtListAnd(parts[0], parts[1]) : parts.single,
    );
  }

  /// "4 h", "1 h 30 min", "45 min".
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % Duration.minutesPerHour;
    if (hours == 0) return _l10n.fmtMinutes(minutes);
    return minutes == 0
        ? _l10n.fmtHours(hours)
        : _l10n.fmtHoursMinutes(hours, minutes);
  }

  /// "★ 4.7 · 12 ratings", or "New driver" before anyone has rated them.
  static String driverRating(MyBooking b) {
    final rating = b.driverRating;
    if (rating == null || b.driverRatingCount == 0) return _l10n.fmtNewDriver;
    return _l10n.fmtDriverRating(
      rating.toStringAsFixed(1),
      b.driverRatingCount,
    );
  }

  /// "KA01AB1234 · Sedan · Manual", from whatever the server sent.
  static String? car(MyBooking b) {
    final l10n = _l10n;
    final parts = [
      ?b.carRegistration,
      if (b.carType case final type?) type.labelIn(l10n),
      if (b.transmission case final gearbox?) gearbox.labelIn(l10n),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
