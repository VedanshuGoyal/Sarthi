import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

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
        color: SarthiColors.ultramarineWash,
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
      ),
      child: Column(
        children: [
          _RouteEnd(
            icon: Icons.trip_origin,
            label: 'From',
            address: startAddress,
          ),
          const SizedBox(height: 12),
          _RouteEnd(
            icon: Icons.place_outlined,
            label: 'To',
            address: destinationAddress,
          ),
        ],
      ),
    );
  }
}

class _RouteEnd extends StatelessWidget {
  const _RouteEnd({
    required this.icon,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
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
