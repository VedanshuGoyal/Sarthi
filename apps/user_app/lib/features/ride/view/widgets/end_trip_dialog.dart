import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/my_booking.dart';

/// Asks whether to end [booking]'s trip now; resolves true when the
/// customer confirms, false when they keep going.
Future<bool> showEndTripDialog(BuildContext context, MyBooking booking) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => EndTripDialog(booking: booking),
  );
  return confirmed ?? false;
}

/// "End trip now?": what ending now costs — by the hour for the time used,
/// each started hour counted as a full one, and past the booked time (after
/// [overtimeGrace]) the extra hours too — and a choice between ending and
/// keeping going. Pops with true on confirm; the caller ends the trip.
class EndTripDialog extends StatelessWidget {
  const EndTripDialog({super.key, required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.endTripTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.endTripByTheHour, style: t.body(color: t.ink)),
          const SizedBox(height: Skyline.s8),
          Text(l10n.endTripOvertime(overtimeGrace.inMinutes), style: t.body()),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.endTripKeepGoing),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.endTripNow),
        ),
      ],
    );
  }
}
