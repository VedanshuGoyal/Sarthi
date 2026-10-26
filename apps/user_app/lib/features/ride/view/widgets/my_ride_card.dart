import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';
import 'booking_status_pill.dart';
import 'driver_row.dart';
import 'ride_format.dart';
import 'star_rating.dart';
import 'start_code_panel.dart';

/// One booking. While it's active: the driver (with a call button that hands
/// off to the phone's dialer) and the start code; once it's completed: who
/// drove, the fare, whether it's paid — or a "Pay by UPI" button — and the
/// stars given — or a "Rate your trip" prompt;
/// once cancelled: who cancelled and why. Renders data only; [onTap] opens
/// the ride and [onRate] its rating.
class MyRideCard extends StatelessWidget {
  const MyRideCard({
    super.key,
    required this.booking,
    this.onTap,
    this.onRate,
    this.onPay,
  });

  final MyBooking booking;
  final VoidCallback? onTap;

  /// Pays for a completed ride that's due; defaults to [onTap], which opens
  /// the ride and its pay button.
  final VoidCallback? onPay;

  /// Asks for the stars of an unrated, completed ride.
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final b = booking;
    final destination = b.destinationAddress;
    final waitingForDriver = b.status == BookingStatus.requested;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: BorderRadius.circular(Skyline.radiusSm),
                ),
                child: Icon(
                  RideFormat.tripIcon(b.tripType),
                  color: t.primaryText,
                  size: 20,
                ),
              ),
              const SizedBox(width: Skyline.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(RideFormat.tripLabel(b.tripType), style: t.title(15)),
                    Text(
                      RideFormat.when(context, b.scheduledAt),
                      style: t.body(size: 13),
                    ),
                  ],
                ),
              ),
              BookingStatusPill(status: b.status),
            ],
          ),
          const SizedBox(height: Skyline.s12),
          Text(
            destination == null
                ? b.pickupAddress
                : '${b.pickupAddress}  →  $destination',
            style: t.body(size: 13.5, color: t.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (b.stopCount > 0)
            Text(
              '${b.stopCount} ${b.stopCount == 1 ? 'stop' : 'stops'}',
              style: t.body(size: 13),
            ),
          const SizedBox(height: Skyline.s12),
          if (b.status == BookingStatus.completed) ...[
            _CompletedRow(
              driverName: b.driverName,
              fare: RideFormat.fare(b),
              paid: b.paymentStatus == RidePaymentStatus.paid,
            ),
            const SizedBox(height: Skyline.s8),
            if (b.paymentStatus == RidePaymentStatus.due) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onPay ?? onTap,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text('Pay ₹${b.fareRupees} by UPI'),
                ),
              ),
              const SizedBox(height: Skyline.s4),
            ],
            if (b.myRating case final rating?)
              Row(
                children: [
                  Text('You rated ', style: t.body(size: 13)),
                  StarRow(stars: rating.stars, size: 16),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRate ?? onTap,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: const Text('Rate your trip'),
                ),
              ),
          ] else if (b.status == BookingStatus.cancelled)
            Text(
              b.cancellationSummary ?? 'This ride was cancelled.',
              style: t.body(size: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else if (b.status == BookingStatus.expired)
            Text(
              'No driver accepted in time. Please book again.',
              style: t.body(size: 13),
            )
          else if (waitingForDriver)
            Row(
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.signal,
                  ),
                ),
                const SizedBox(width: Skyline.s8),
                Expanded(
                  child: Text(
                    "We'll show your driver here as soon as one accepts.",
                    style: t.body(size: 13),
                  ),
                ),
              ],
            )
          else if (b.driverName != null)
            DriverRow(name: b.driverName!, phone: b.driverPhone),
          if (b.startOtp != null) ...[
            const SizedBox(height: Skyline.s12),
            StartCodePanel(code: b.startOtp!),
          ],
        ],
      ),
    );
  }
}

/// A completed trip's footer: who drove, what it cost, and whether it's paid.
class _CompletedRow extends StatelessWidget {
  const _CompletedRow({
    required this.driverName,
    required this.fare,
    this.paid = false,
  });

  final String? driverName;
  final String fare;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            driverName == null ? 'Trip completed' : 'Driven by $driverName',
            style: t.body(size: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Skyline.s12),
        if (paid) ...[
          Icon(Icons.check_circle_rounded, size: 16, color: t.success),
          const SizedBox(width: 4),
          Text('Paid', style: t.label(color: t.success)),
          const SizedBox(width: Skyline.s8),
        ],
        Text(fare, style: t.title(15)),
      ],
    );
  }
}
