import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';
import 'booking_status_pill.dart';
import 'driver_row.dart';
import 'ride_format.dart';
import 'ride_note.dart';
import 'star_rating.dart';
import 'start_code_panel.dart';

/// One booking. While it's active: the driver (with a call button that hands
/// off to the phone's dialer) and the start code; once it's completed: who
/// drove, the fare (and that it ended early or ran past the booked time, if
/// it did), whether it's paid — or a "Pay by UPI" button — and the stars
/// given — or a "Rate your trip" prompt; once cancelled: who cancelled and
/// why, and any cancellation fee with its own "Pay by UPI" button while it's
/// due. A Pay button is for the total, with what's [carried] from other
/// bookings named under it; an active ride says what will be added to its
/// payment. Renders data only; [onTap] opens the ride and [onRate] its
/// rating.
class MyRideCard extends StatelessWidget {
  const MyRideCard({
    super.key,
    required this.booking,
    this.onTap,
    this.onRate,
    this.onPay,
    this.driverPhoto,
    this.carried,
  });

  final MyBooking booking;

  /// What paying for [booking] also collects for the customer's other
  /// bookings; when null, its `carriedPaise`, worded as from other rides.
  final EarlierDues? carried;

  /// The driver's photo, when the booking has a driver with one.
  final ImageProvider? driverPhoto;
  final VoidCallback? onTap;

  /// Pays for a completed ride (or a cancellation fee) that's due; defaults
  /// to [onTap], which opens the ride and its pay button.
  final VoidCallback? onPay;

  /// Asks for the stars of an unrated, completed ride.
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final b = booking;
    final destination = b.destinationAddress;
    final waitingForDriver = b.status == BookingStatus.requested;
    final carried =
        this.carried ??
        (b.carriedPaise > 0 ? (paise: b.carriedPaise, oneRide: false) : null);
    final payButton = _PayButton(
      amountPaise: b.totalDuePaise,
      includes: carried == null ? null : RideFormat.carriedIncluded(carried),
      onPressed: onPay ?? onTap,
    );
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
            _ChargeRow(
              label: b.driverName == null
                  ? 'Trip completed'
                  : 'Driven by ${b.driverName}',
              amount: RideFormat.fare(b),
              paid: b.paymentStatus == RidePaymentStatus.paid,
            ),
            if (RideFormat.endedEarly(b) case final early?)
              Text('Ended early. $early', style: t.body(size: 13)),
            if (RideFormat.ranOver(b) case final over?)
              Text(over, style: t.body(size: 13)),
            const SizedBox(height: Skyline.s8),
            if (b.paymentStatus == RidePaymentStatus.due) ...[
              payButton,
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
          ] else if (b.status == BookingStatus.cancelled) ...[
            Text(
              b.cancellationSummary ?? 'This ride was cancelled.',
              style: t.body(size: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (b.hasCancellationFee) ...[
              const SizedBox(height: Skyline.s8),
              _ChargeRow(
                label: 'Cancellation fee',
                amount: RideFormat.rupees(b.cancellationFeePaise),
                paid: b.paymentStatus == RidePaymentStatus.paid,
              ),
              if (b.paymentStatus == RidePaymentStatus.due) ...[
                const SizedBox(height: Skyline.s8),
                payButton,
              ],
            ],
          ] else if (b.status == BookingStatus.expired)
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
            DriverRow(
              name: b.driverName!,
              phone: b.driverPhone,
              photo: driverPhoto,
            ),
          if (b.startOtp != null) ...[
            const SizedBox(height: Skyline.s12),
            StartCodePanel(code: b.startOtp!),
          ],
          if (carried != null && b.status.isActive) ...[
            const SizedBox(height: Skyline.s12),
            RideNote(text: RideFormat.carriedNote(carried)),
          ],
        ],
      ),
    );
  }
}

/// "Pay ₹640 by UPI", for whatever paying for the booking collects, and
/// the [includes] line naming what's from other rides.
class _PayButton extends StatelessWidget {
  const _PayButton({required this.amountPaise, this.includes, this.onPressed});

  final int amountPaise;
  final String? includes;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: Text('Pay ${RideFormat.rupees(amountPaise)} by UPI'),
        ),
        if (includes case final line?) ...[
          const SizedBox(height: Skyline.s4),
          Text(line, style: t.body(size: 13)),
        ],
      ],
    );
  }
}

/// A finished booking's footer: what was charged — who drove, or that it's
/// a cancellation fee — how much, and whether it's paid.
class _ChargeRow extends StatelessWidget {
  const _ChargeRow({
    required this.label,
    required this.amount,
    this.paid = false,
  });

  final String label;
  final String amount;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
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
        Text(amount, style: t.title(15)),
      ],
    );
  }
}
