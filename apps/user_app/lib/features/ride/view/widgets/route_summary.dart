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
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Skyline.s16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Skyline.radiusLg),
        boxShadow: t.cardShadow,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The route rail: start dot, joining line, destination pin.
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.signal, width: 3),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: t.hairline,
                    ),
                  ),
                  Icon(Icons.place_rounded, size: 18, color: t.primary),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            const SizedBox(width: Skyline.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RouteEnd(label: 'From', address: startAddress),
                  Divider(height: Skyline.s24, color: t.hairline),
                  _RouteEnd(label: 'To', address: destinationAddress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteEnd extends StatelessWidget {
  const _RouteEnd({required this.label, required this.address});

  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.label(size: 12, color: t.primaryText)),
        const SizedBox(height: 2),
        Text(
          address,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.title(14.5, weight: FontWeight.w600),
        ),
      ],
    );
  }
}
