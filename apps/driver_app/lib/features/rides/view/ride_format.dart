import 'package:flutter/material.dart';

import '../domain/ride.dart';

/// Display formatting for rides: rupees, times, days, durations, distances.
/// Pure functions of their inputs, so panels and cards stay consistent.
abstract final class RideFormat {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

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

  /// 9:05 AM
  static String time(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Today / Tomorrow / Yesterday / Mon, 26 Oct
  static String day(DateTime t, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final diff = _dateOnly(t).difference(today).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]}',
    };
  }

  /// Tomorrow · 9:00 AM
  static String when(DateTime t, {DateTime? now}) =>
      '${day(t, now: now)} · ${time(t)}';

  /// 45 min / 3 h / 1 h 45 min
  static String duration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// 700 m / 7.7 km / 24 km
  static String distance(double meters) {
    if (meters < 1000) return '${(meters / 50).round() * 50} m';
    final km = meters / 1000;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  /// "in 25 min", "in 3 h", "25 min ago" — how far [t] is from [now].
  static String relative(DateTime t, {DateTime? now}) {
    final diff = t.difference(now ?? DateTime.now());
    final label = duration(Duration(minutes: diff.inMinutes.abs()));
    if (diff.inMinutes.abs() < 1) return 'now';
    if (diff.inHours.abs() >= 24) return day(t, now: now);
    return diff.isNegative ? '$label ago' : 'in $label';
  }

  /// What the ride books the driver for: "3 h hire", "~45 min drive",
  /// "2 stops · 1 h 45 min".
  static String span(Ride ride) => switch (ride.kind) {
    TripKind.roundTrip => '${ride.hours ?? ride.duration.inHours} h hire',
    TripKind.oneWay =>
      '~${duration(Duration(minutes: ride.estimatedMinutes ?? ride.duration.inMinutes))} drive',
    TripKind.multiStop =>
      '${ride.stops.length} ${ride.stops.length == 1 ? 'stop' : 'stops'} · ${duration(ride.duration)}',
  };

  /// +91 98765 43210
  static String phone(String e164) {
    if (e164.startsWith('+91') && e164.length == 13) {
      return '+91 ${e164.substring(3, 8)} ${e164.substring(8)}';
    }
    return e164;
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// The icon for each trip kind — the same set the customer app's trip
/// chooser uses, so both sides of a booking read alike.
IconData tripKindIcon(TripKind kind) => switch (kind) {
  TripKind.oneWay => Icons.arrow_forward_rounded,
  TripKind.roundTrip => Icons.schedule_rounded,
  TripKind.multiStop => Icons.alt_route_rounded,
};
