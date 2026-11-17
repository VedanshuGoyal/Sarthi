import 'package:flutter/material.dart';

import '../../domain/my_booking.dart';
import '../../domain/trip_type.dart';
import 'car_options_fields.dart';

/// How the ride cards and the ride details screen word a booking — shared so
/// a ride reads the same in the list and on its own screen.
abstract final class RideFormat {
  static IconData tripIcon(TripType type) => switch (type) {
    TripType.oneWay => Icons.arrow_forward_rounded,
    TripType.roundTrip => Icons.schedule_rounded,
    TripType.multiStop => Icons.alt_route_rounded,
  };

  static String tripLabel(TripType type) => switch (type) {
    TripType.oneWay => 'One-Way',
    TripType.roundTrip => 'Round Trip',
    TripType.multiStop => 'Multi-Stop',
  };

  /// "Today, 9:30 AM", "Tomorrow, …", or "Mon, Oct 26, …" further out.
  static String when(BuildContext context, DateTime at) {
    final l10n = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final days = DateTime(
      at.year,
      at.month,
      at.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final day = switch (days) {
      -1 => 'Yesterday',
      0 => 'Today',
      1 => 'Tomorrow',
      _ => l10n.formatMediumDate(at),
    };
    return '$day, ${time(context, at)}';
  }

  /// "9:30 AM".
  static String time(BuildContext context, DateTime at) =>
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(at));

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
    return 'Charged ${rupees(b.farePaise)} for the time used '
        '(booked ${rupees(booked)}).';
  }

  /// "Ran past the booked time. Charged ₹960 for 4 h (booked ₹640).", for
  /// a trip that went over its booked hours; null for any other.
  static String? ranOver(MyBooking b) {
    final booked = b.bookedFarePaise;
    if (!b.ranOver || booked == null) return null;
    final hours = b.hoursUsed;
    return 'Ran past the booked time. Charged ${rupees(b.farePaise)}'
        '${hours == null ? '' : ' for $hours h'} (booked ${rupees(booked)}).';
  }

  /// The ride screen's note while a trip is past its booked time.
  static const String pastBookedTime =
      "You're past your booked time. Extra time is charged by the hour.";

  /// "₹50 unpaid from an earlier ride will be added when you pay for this
  /// trip.": on an upcoming or ongoing ride — or one about to be booked —
  /// while the customer owes on earlier ones.
  static String carriedNote(EarlierDues dues) =>
      '${rupees(dues.paise)} unpaid from '
      '${dues.oneRide ? 'an earlier ride' : 'earlier rides'} '
      'will be added when you pay for this trip.';

  /// "Includes ₹50 from another ride.", by the Pay button of a ride whose
  /// payment also clears what's owed on the customer's other bookings.
  static String carriedIncluded(EarlierDues dues) =>
      'Includes ${rupees(dues.paise)} from '
      '${dues.oneRide ? 'another ride' : 'other rides'}.';

  /// "4 h", "1 h 30 min", "45 min".
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % Duration.minutesPerHour;
    if (hours == 0) return '$minutes min';
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  /// "★ 4.7 · 12 ratings", or "New driver" before anyone has rated them.
  static String driverRating(MyBooking b) {
    final rating = b.driverRating;
    if (rating == null || b.driverRatingCount == 0) return 'New driver';
    final count = b.driverRatingCount;
    return '★ ${rating.toStringAsFixed(1)} · $count '
        '${count == 1 ? 'rating' : 'ratings'}';
  }

  /// "KA01AB1234 · Sedan · Manual", from whatever the server sent.
  static String? car(MyBooking b) {
    final parts = [
      ?b.carRegistration,
      if (b.carType case final type?) CarOptionsFields.carTypeLabel(type),
      if (b.transmission case final gearbox?)
        CarOptionsFields.transmissionLabel(gearbox),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
