import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';
import 'ride_format.dart';

/// The receipt of a paid ride: the fare (with its base and night parts when
/// the server sent them), how it was paid, the reference to quote if it's
/// ever disputed, and when.
///
/// Renders [booking] only; rows the server didn't send are left out, so a
/// receipt from an older server is just the fare and the time.
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final b = booking;
    final payment = b.payment;
    final breakdown = b.fareBreakdown;
    final paidAt = payment?.paidAt ?? b.paidAt;
    final mono = t.body(size: 12.5).copyWith(fontFamily: 'monospace');
    // (label, value, style); null style is the regular value style.
    final rows = <(String, String, TextStyle?)>[
      ('Fare', '₹${b.fareRupees}', t.title(16)),
      if (breakdown != null) ...[
        ('Base fare', '₹${breakdown.baseRupees}', null),
        if (breakdown.nightPaise > 0)
          ('Night surcharge', '₹${breakdown.nightRupees}', null),
      ],
      ('Paid via', payment?.modeLabel ?? 'UPI', null),
      if (payment?.reference case final reference?)
        ('Reference', reference, mono),
      if (payment?.merchantOrderId case final order?) ('Order', order, mono),
      if (paidAt != null) ('Paid', RideFormat.when(context, paidAt), null),
    ];
    return SkylineSection(
      title: 'Receipt',
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: t.success, size: 20),
              const SizedBox(width: Skyline.s8),
              Expanded(
                child: Text(
                  'Paid. Thank you!',
                  style: t.title(14, color: t.success),
                ),
              ),
            ],
          ),
          for (final (label, value, style) in rows) ...[
            const SizedBox(height: Skyline.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label, style: t.body(size: 13.5))),
                const SizedBox(width: Skyline.s12),
                Flexible(
                  flex: 2,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: style ?? t.title(13.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
