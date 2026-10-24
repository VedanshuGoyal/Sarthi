import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// The card docked over the map that reports what the centre pin currently
/// points at and lets the customer confirm it.
///
/// Pure presentation per the reusable-widget guideline: it renders the passed
/// state and emits [onConfirm] — it holds no map, does no lookup. That keeps it
/// previewable on its own, away from the platform map view.
class MapPinCard extends StatelessWidget {
  const MapPinCard({
    super.key,
    this.caption = 'Pickup here',
    required this.label,
    required this.isMoving,
    required this.isResolving,
    this.error,
    required this.canConfirm,
    this.onConfirm,
  });

  /// What the pinned place is for ("Pickup here", "Destination"…).
  final String caption;

  /// Address (or raw coordinates) under the pin.
  final String label;

  /// The user is panning — show a muted "keep moving" hint, not a stale label.
  final bool isMoving;

  /// A reverse-geocode is in flight for the settled centre.
  final bool isResolving;

  /// User-safe message when the last resolve failed.
  final String? error;

  final bool canConfirm;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Skyline.radiusXl),
        ),
        boxShadow: t.floatShadow,
      ),
      padding: const EdgeInsets.fromLTRB(
        Skyline.s20,
        Skyline.s12,
        Skyline.s20,
        Skyline.s20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: t.outline,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: Skyline.s16),
          Container(
            padding: const EdgeInsets.all(Skyline.s12),
            decoration: BoxDecoration(
              color: t.sunken,
              borderRadius: BorderRadius.circular(Skyline.radius),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: BorderRadius.circular(Skyline.radiusSm),
                  ),
                  child: Icon(Icons.place_rounded, color: t.primaryText),
                ),
                const SizedBox(width: Skyline.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caption, style: t.label(size: 12)),
                      const SizedBox(height: 2),
                      _detail(t),
                    ],
                  ),
                ),
                if (isResolving && !isMoving) ...[
                  const SizedBox(width: Skyline.s8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: Skyline.s8),
            Text(error!, style: t.body(size: 13, color: t.danger)),
          ],
          const SizedBox(height: Skyline.s16),
          SarthiPrimaryButton(
            label: 'Confirm this location',
            onPressed: canConfirm ? onConfirm : null,
          ),
        ],
      ),
    );
  }

  Widget _detail(SkylineTokens t) {
    if (isMoving) {
      return Text('Move the map to place the pin', style: t.body(size: 14));
    }
    return Text(
      label,
      style: t.title(15),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
