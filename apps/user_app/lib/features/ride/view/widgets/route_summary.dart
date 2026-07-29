import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'vast_quiet/vast_quiet_theme.dart';

/// A compact, read-only banner echoing both ends of the route chosen on the
/// earlier location steps. The One-Way details and review screens share it so
/// the route reads the same on every step.
///
/// State-free per the reusable-widget guideline: addresses in, nothing out.
class RouteSummary extends StatelessWidget {
  const RouteSummary({
    super.key,
    required this.startAddress,
    required this.destinationAddress,
  });

  final String startAddress;
  final String destinationAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RideSurfaces.washOf(context),
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
      ),
      child: Column(
        children: [
          _RouteEnd(
            marker: _originDot,
            label: 'From',
            address: startAddress,
          ),
          const SizedBox(height: 12),
          _RouteEnd(
            marker: _destPin,
            label: 'To',
            address: destinationAddress,
          ),
        ],
      ),
    );
  }
}

/// Origin green, destination red — the universal start/end reading, echoing
/// the colours of the two pins [RouteMap] drops.
const _originColor = Color(0xFF2E7D32);
const _destColor = Color(0xFFC62828);

/// A small filled green dot for the pickup end — understated where a full
/// [Icons.trip_origin] ring read as heavy.
Widget _originDot(BuildContext context) => Container(
  width: 10,
  height: 10,
  decoration: const BoxDecoration(
    color: _originColor,
    shape: BoxShape.circle,
  ),
);

/// A compact drop pin for the destination end.
Widget _destPin(BuildContext context) =>
    const Icon(Icons.location_on, size: 15, color: _destColor);

class _RouteEnd extends StatelessWidget {
  const _RouteEnd({
    required this.marker,
    required this.label,
    required this.address,
  });

  /// Builds the small leading symbol for this end (dot or pin).
  final WidgetBuilder marker;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        // Fixed leading box so labels align whatever the symbol's size.
        SizedBox(width: 18, child: Center(child: marker(context))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
