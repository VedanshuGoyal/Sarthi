import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/ride.dart';
import '../ride_format.dart';

/// The ride's status as a small coloured pill.
class RideStatusChip extends StatelessWidget {
  const RideStatusChip({super.key, required this.status});

  final RideStatus status;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final (bg, fg) = switch (status) {
      RideStatus.requested => (t.primarySoft, t.primaryText),
      RideStatus.accepted => (t.sunken, t.ink),
      RideStatus.arrived || RideStatus.inProgress => (t.primary, t.onPrimary),
      RideStatus.completed => (t.success.withValues(alpha: 0.12), t.success),
      RideStatus.cancelled => (t.danger.withValues(alpha: 0.10), t.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.label, style: t.label(size: 12, color: fg)),
    );
  }
}

/// The trip kind's icon in a tinted well, with its label.
class TripKindBadge extends StatelessWidget {
  const TripKindBadge({super.key, required this.kind});

  final TripKind kind;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: t.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(tripKindIcon(kind), size: 18, color: t.primaryText),
        ),
        const SizedBox(width: Skyline.s8),
        Text(kind.label, style: t.title(14)),
      ],
    );
  }
}

/// A small icon + text fact ("Sedan · Automatic", "7.7 km away").
class RideFact extends StatelessWidget {
  const RideFact({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: t.inkFaint),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: t.body(size: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The route as a vertical timeline: pickup, any stops, and where it ends.
///
/// [compact] shows only the first and last place (with a "+N stops" note),
/// for list cards; the full form lists every stop with its errand and
/// leave-by time.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({super.key, required this.ride, this.compact = false});

  final Ride ride;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final rows = <_RouteRow>[
      _RouteRow(
        place: ride.pickup,
        caption: 'Pickup · ${RideFormat.time(ride.scheduledAt)}',
        marker: _Marker.start,
      ),
    ];
    if (ride.kind == TripKind.multiStop) {
      if (compact && ride.stops.length > 1) {
        rows.add(
          _RouteRow(
            place: ride.stops.last.place,
            caption:
                'Last of ${ride.stops.length} stops'
                '${_by(ride.stops.last.departBy)}',
            marker: _Marker.end,
          ),
        );
      } else {
        for (final (i, stop) in ride.stops.indexed) {
          final last = i == ride.stops.length - 1;
          rows.add(
            _RouteRow(
              place: stop.place,
              caption:
                  [
                    'Stop ${i + 1}',
                    if (stop.task.isNotEmpty) stop.task,
                  ].join(' · ') +
                  _by(stop.departBy),
              marker: last ? _Marker.end : _Marker.stop,
            ),
          );
        }
      }
    } else if (ride.destination != null) {
      rows.add(
        _RouteRow(
          place: ride.destination!,
          caption: 'Drop · ~${RideFormat.time(ride.endsAt)}',
          marker: _Marker.end,
        ),
      );
    } else {
      rows.add(
        _RouteRow(
          place: ride.pickup,
          caption: 'Back at pickup · ~${RideFormat.time(ride.endsAt)}',
          marker: _Marker.end,
        ),
      );
    }

    return Column(
      children: [
        for (final (i, row) in rows.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      row.marker.build(t),
                      if (i < rows.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: t.hairline,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Skyline.s12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < rows.length - 1 ? Skyline.s12 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          compact ? row.place.shortName : row.place.address,
                          style: t.title(compact ? 14 : 15),
                          maxLines: compact ? 1 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(row.caption, style: t.body(size: 12.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _by(DateTime? departBy) =>
      departBy == null ? '' : ' · leave by ${RideFormat.time(departBy)}';
}

enum _Marker {
  start,
  stop,
  end;

  Widget build(SkylineTokens t) => switch (this) {
    _Marker.start => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: t.signal,
        shape: BoxShape.circle,
        border: Border.all(color: t.primarySoft, width: 3),
      ),
    ),
    _Marker.stop => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: t.surface,
        shape: BoxShape.circle,
        border: Border.all(color: t.outline, width: 2),
      ),
    ),
    _Marker.end => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  };
}

class _RouteRow {
  const _RouteRow({
    required this.place,
    required this.caption,
    required this.marker,
  });

  final RidePlace place;
  final String caption;
  final _Marker marker;
}

/// One ride in a list: kind, when, fare, the route, and the car. Used by the
/// Rides panel and as the base of request cards. [footer] adds actions.
class RideCard extends StatelessWidget {
  const RideCard({
    super.key,
    required this.ride,
    this.onTap,
    this.footer,
    this.showStatus = true,
  });

  final Ride ride;
  final VoidCallback? onTap;
  final Widget? footer;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final car = ride.car;
    final distance = ride.distanceM;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TripKindBadge(kind: ride.kind),
              const Spacer(),
              if (showStatus) RideStatusChip(status: ride.status),
            ],
          ),
          const SizedBox(height: Skyline.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      RideFormat.when(ride.scheduledAt),
                      style: t.title(17, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(RideFormat.span(ride), style: t.body(size: 13)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(RideFormat.rupees(ride.fareRupees), style: t.figure(22)),
                  if (ride.fareEstimated)
                    Text('estimate', style: t.body(size: 11.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: Skyline.s16),
          RouteTimeline(ride: ride, compact: true),
          const SizedBox(height: Skyline.s12),
          Wrap(
            spacing: Skyline.s16,
            runSpacing: Skyline.s4,
            children: [
              if (car != null)
                RideFact(
                  icon: Icons.directions_car_filled_rounded,
                  text: [
                    car.carTypeLabel,
                    if (car.transmissionLabel.isNotEmpty) car.transmissionLabel,
                  ].join(' · '),
                ),
              if (distance != null)
                RideFact(
                  icon: Icons.near_me_rounded,
                  text: '${RideFormat.distance(distance)} away',
                ),
            ],
          ),
          if (ride.status == RideStatus.cancelled) ...[
            const SizedBox(height: Skyline.s12),
            Row(
              children: [
                Icon(Icons.cancel_rounded, size: 16, color: t.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      ride.cancelledBy == 'customer'
                          ? 'Cancelled by customer'
                          : 'Cancelled',
                      if (ride.cancelReason?.isNotEmpty ?? false)
                        ride.cancelReason!,
                    ].join(' · '),
                    style: t.body(size: 12.5, color: t.danger),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else if (footer != null) ...[
            const SizedBox(height: Skyline.s16),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// A friendly empty or error state: an icon in a well, a title and a line.
class PanelMessage extends StatelessWidget {
  const PanelMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Skyline.s24,
        vertical: Skyline.s32,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(Skyline.radius),
            ),
            child: Icon(icon, size: 30, color: t.primaryText),
          ),
          const SizedBox(height: Skyline.s16),
          Text(title, style: t.title(17), textAlign: TextAlign.center),
          const SizedBox(height: Skyline.s4),
          Text(body, style: t.body(), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: Skyline.s16), action!],
        ],
      ),
    );
  }
}

/// Five stars, read-only — what a rating of [stars] (1–5) looks like.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 16});

  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= stars ? t.signal : t.outline,
          ),
      ],
    );
  }
}

/// Five tappable stars for giving a rating — tapping the third star sets
/// [value] to 3, and so on.
class StarPicker extends StatelessWidget {
  const StarPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: () => onChanged(i),
            icon: Icon(
              i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i <= value ? t.signal : t.outline,
            ),
            iconSize: 32,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
      ],
    );
  }
}

/// A bold section heading with an optional trailing widget (a count, a link).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Skyline.s12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.title(17))),
          ?trailing,
        ],
      ),
    );
  }
}
