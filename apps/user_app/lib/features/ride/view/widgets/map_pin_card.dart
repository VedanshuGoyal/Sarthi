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
    required this.label,
    required this.isMoving,
    required this.isResolving,
    this.error,
    required this.canConfirm,
    this.onConfirm,
  });

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
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pickup here',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            _detail(theme),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SarthiPrimaryButton(
              label: 'Confirm this location',
              onPressed: canConfirm ? onConfirm : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(ThemeData theme) {
    if (isMoving) {
      return Text(
        'Move the map to place the pin',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.place_outlined, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isResolving) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}
