import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/my_booking.dart';
import '../../domain/trip_type.dart';
import '../../ride_providers.dart';
import '../../view_model/my_bookings_view_model.dart';

/// The home screen's "Your rides" section: each unfinished booking with its
/// status, the driver once one accepts, and the start code to give them.
///
/// Renders nothing while the customer has no active bookings, so a new
/// customer's home stays about booking. The signed-in shell keeps the list
/// fresh (see [MyBookingsViewModel.startPolling]).
class MyRidesSection extends ConsumerWidget {
  const MyRidesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(myBookingsViewModelProvider).active;
    if (active.isEmpty) return const SizedBox.shrink();
    final t = SkylineTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your rides', style: t.title(16)),
        const SizedBox(height: Skyline.s12),
        for (final booking in active) ...[
          MyRideCard(booking: booking),
          const SizedBox(height: Skyline.s12),
        ],
        const SizedBox(height: Skyline.s12),
      ],
    );
  }
}

/// One booking. While it's active: the driver (with a call button that hands
/// off to the phone's dialer) and the start code; once it's completed: who
/// drove and the fare. Renders data only.
class MyRideCard extends StatelessWidget {
  const MyRideCard({super.key, required this.booking});

  final MyBooking booking;

  static IconData _icon(TripType type) => switch (type) {
    TripType.oneWay => Icons.arrow_forward_rounded,
    TripType.roundTrip => Icons.schedule_rounded,
    TripType.multiStop => Icons.alt_route_rounded,
  };

  static String _label(TripType type) => switch (type) {
    TripType.oneWay => 'One-Way',
    TripType.roundTrip => 'Round Trip',
    TripType.multiStop => 'Multi-Stop',
  };

  static String _when(BuildContext context, DateTime at) {
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
    return '$day, ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final b = booking;
    final destination = b.destinationAddress;
    final waitingForDriver = b.status == BookingStatus.requested;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
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
                child: Icon(_icon(b.tripType), color: t.primaryText, size: 20),
              ),
              const SizedBox(width: Skyline.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_label(b.tripType), style: t.title(15)),
                    Text(
                      _when(context, b.scheduledAt),
                      style: t.body(size: 13),
                    ),
                  ],
                ),
              ),
              _StatusPill(status: b.status),
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
          // A cancelled booking ends at its route; nothing more to show.
          if (b.status != BookingStatus.cancelled)
            const SizedBox(height: Skyline.s12),
          if (b.status == BookingStatus.completed)
            _CompletedRow(
              driverName: b.driverName,
              fare: b.fareEstimated ? '≈ ₹${b.fareRupees}' : '₹${b.fareRupees}',
            )
          else if (b.status == BookingStatus.cancelled)
            const SizedBox.shrink()
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
            _DriverRow(name: b.driverName!, phone: b.driverPhone),
          if (b.startOtp != null) ...[
            const SizedBox(height: Skyline.s12),
            _StartCode(code: b.startOtp!),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final strong =
        status == BookingStatus.arrived || status == BookingStatus.inProgress;
    final (fill, ink) = switch (status) {
      _ when strong => (t.primary, t.onPrimary),
      BookingStatus.completed => (t.sunken, t.success),
      BookingStatus.cancelled => (t.sunken, t.inkMuted),
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

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.name, required this.phone});

  final String name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final phone = this.phone;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: t.sunken,
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: t.title(14, color: t.primaryText),
          ),
        ),
        const SizedBox(width: Skyline.s12),
        Expanded(
          child: Text(
            '$name is your driver',
            style: t.title(14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (phone != null)
          IconButton.filled(
            tooltip: 'Call driver',
            style: IconButton.styleFrom(
              backgroundColor: t.primarySoft,
              foregroundColor: t.primaryText,
            ),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.call_rounded, size: 20),
          ),
      ],
    );
  }
}

/// A completed trip's footer: who drove, and what it cost.
class _CompletedRow extends StatelessWidget {
  const _CompletedRow({required this.driverName, required this.fare});

  final String? driverName;
  final String fare;

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
        Text(fare, style: t.title(15)),
      ],
    );
  }
}

/// The start code, big and spaced out so it can be read aloud.
class _StartCode extends StatelessWidget {
  const _StartCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Semantics(
      label: 'Start code ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Skyline.s16,
          vertical: Skyline.s12,
        ),
        decoration: BoxDecoration(
          color: t.primary,
          borderRadius: BorderRadius.circular(Skyline.radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start code',
                    style: t.label(size: 13, color: t.onPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share it with your driver when you meet.',
                    style: t.body(
                      size: 12.5,
                      color: t.onPrimary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Skyline.s12),
            Text(
              code.split('').join(' '),
              style: t.figure(28, color: t.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
