import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';

/// A booking's status as a small rounded tag — solid while the driver is at
/// the pickup or on the trip, muted once it's over.
class BookingStatusPill extends StatelessWidget {
  const BookingStatusPill({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final strong =
        status == BookingStatus.arrived || status == BookingStatus.inProgress;
    final (fill, ink) = switch (status) {
      _ when strong => (t.primary, t.onPrimary),
      BookingStatus.completed => (t.sunken, t.success),
      BookingStatus.cancelled ||
      BookingStatus.expired => (t.sunken, t.inkMuted),
      _ => (t.primarySoft, t.primaryText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.label, style: t.label(size: 12, color: ink)),
    );
  }
}
