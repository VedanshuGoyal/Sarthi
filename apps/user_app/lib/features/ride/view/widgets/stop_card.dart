import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'schedule_field.dart';

/// One stop in the Multi-Stop planner: where to go, the driver's task there,
/// and the leave-by deadline — plus reorder/remove controls in the header.
///
/// State-free per the reusable-widget guideline: the parent owns the
/// [taskController] and every value; this card only renders them and emits
/// events. [index] is the 1-based position shown in the badge.
class StopCard extends StatelessWidget {
  const StopCard({
    super.key,
    required this.index,
    required this.address,
    required this.taskController,
    required this.departBy,
    this.timeError,
    required this.canRemove,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onPickLocation,
    required this.onTaskChanged,
    required this.onTapDate,
    required this.onTapTime,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;

  /// The chosen place, or null to show the "Choose location" placeholder.
  final String? address;

  final TextEditingController taskController;

  /// The leave-by deadline, or null until one is picked.
  final DateTime? departBy;

  /// Shown under the schedule when this deadline breaks the timeline order.
  final String? timeError;

  final bool canRemove;
  final bool canMoveUp;
  final bool canMoveDown;

  final VoidCallback onPickLocation;
  final ValueChanged<String> onTaskChanged;
  final VoidCallback onTapDate;
  final VoidCallback onTapTime;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primary,
                child: Text(
                  '$index',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Stop $index',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Move stop $index earlier',
                iconSize: 20,
                onPressed: canMoveUp ? onMoveUp : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Move stop $index later',
                iconSize: 20,
                onPressed: canMoveDown ? onMoveDown : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove stop $index',
                iconSize: 20,
                onPressed: canRemove ? onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LocationField(address: address, onTap: onPickLocation),
          const SizedBox(height: 16),
          SarthiTextField(
            label: 'What should the driver do here?',
            controller: taskController,
            hintText: 'e.g. Pick up the parcel from reception',
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
            onChanged: onTaskChanged,
          ),
          const SizedBox(height: 16),
          Text(
            'Leave by',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ScheduleField(
            scheduledAt: departBy,
            onTapDate: onTapDate,
            onTapTime: onTapTime,
          ),
          if (timeError != null) ...[
            const SizedBox(height: 8),
            Text(
              timeError!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// The tappable "where is this stop?" row: the address once chosen, or a
/// placeholder prompting for one. Opens the location picker via [onTap].
class _LocationField extends StatelessWidget {
  const _LocationField({required this.address, required this.onTap});

  final String? address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPlaceholder = address == null;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(SarthiTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SarthiTheme.radius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.place_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  address ?? 'Choose location',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isPlaceholder
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                    fontWeight: isPlaceholder
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
