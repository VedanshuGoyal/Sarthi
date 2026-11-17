import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';
import 'ride_format.dart';

/// Asks whether to end [booking]'s trip now; resolves true when the
/// customer confirms, false when they keep going.
Future<bool> showEndTripDialog(BuildContext context, MyBooking booking) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => EndTripDialog(booking: booking),
  );
  return confirmed ?? false;
}

/// "End trip now?": what ending early costs — by the hour for the time
/// used, each started hour counted as a full one, never more than the
/// booked fare — and a choice between ending and keeping going. Pops with
/// true on confirm; the caller ends the trip.
class EndTripDialog extends StatelessWidget {
  const EndTripDialog({super.key, required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return AlertDialog(
      title: const Text('End trip now?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You'll pay by the hour for the time used. Each started hour "
            'counts as a full hour.',
            style: t.body(color: t.ink),
          ),
          const SizedBox(height: Skyline.s8),
          Text(
            'Never more than your booked fare of '
            '${RideFormat.fare(booking)}.',
            style: t.body(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep going'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('End trip now'),
        ),
      ],
    );
  }
}
