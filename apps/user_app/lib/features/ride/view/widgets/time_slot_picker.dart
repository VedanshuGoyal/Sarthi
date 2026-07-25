import 'package:flutter/material.dart';

import '../../domain/scheduling.dart' as scheduling;

/// Opens the quarter-hour slot picker in a modal bottom sheet and resolves with
/// the chosen slot, or null if the sheet is dismissed. The booking screens use
/// this instead of [showTimePicker] so a trip can only start on a 15-minute
/// boundary — the policy in `domain/scheduling.dart`.
Future<TimeOfDay?> showTimeSlotPicker(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: TimeSlotPicker(
        selected: initial,
        onSelected: (slot) => Navigator.of(sheetContext).pop(slot),
      ),
    ),
  );
}

/// A scrollable list of every quarter-hour start time in a day.
///
/// State-free per the reusable-widget guideline: it renders the slots with
/// [selected] highlighted (snapped onto the grid if it drifted off it) and
/// emits the tapped slot via [onSelected]; the parent owns the sheet and the
/// resulting value. Times are formatted through [MaterialLocalizations] so they
/// follow the device locale.
class TimeSlotPicker extends StatefulWidget {
  const TimeSlotPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TimeOfDay selected;
  final ValueChanged<TimeOfDay> onSelected;

  /// All slots in day order: 00:00, 00:15, … 23:45.
  static const int slotCount =
      TimeOfDay.hoursPerDay *
      TimeOfDay.minutesPerHour ~/
      scheduling.scheduleIntervalMinutes;

  static TimeOfDay slotAt(int index) {
    final minutes = index * scheduling.scheduleIntervalMinutes;
    return TimeOfDay(
      hour: minutes ~/ TimeOfDay.minutesPerHour,
      minute: minutes % TimeOfDay.minutesPerHour,
    );
  }

  /// The slot index nearest to [time] — where the highlight and the initial
  /// scroll position land. Wraps 23:53+ back onto midnight.
  static int nearestSlotIndex(TimeOfDay time) {
    final minutes = time.hour * TimeOfDay.minutesPerHour + time.minute;
    return (minutes / scheduling.scheduleIntervalMinutes).round() % slotCount;
  }

  @override
  State<TimeSlotPicker> createState() => _TimeSlotPickerState();
}

class _TimeSlotPickerState extends State<TimeSlotPicker> {
  static const double _slotExtent = 48;

  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    // Start with the selected slot one row down from the top, so the slots
    // just before it stay reachable at a glance.
    final index = TimeSlotPicker.nearestSlotIndex(widget.selected);
    _controller = ScrollController(
      initialScrollOffset:
          (index - 1).clamp(0, TimeSlotPicker.slotCount - 1) * _slotExtent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = MaterialLocalizations.of(context);
    final selectedIndex = TimeSlotPicker.nearestSlotIndex(widget.selected);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick a start time',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Trips start every 15 minutes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Caps the list at a comfortable height but lets it shrink with the
        // sheet on short windows instead of overflowing.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              controller: _controller,
              itemExtent: _slotExtent,
              itemCount: TimeSlotPicker.slotCount,
              itemBuilder: (context, index) {
                final slot = TimeSlotPicker.slotAt(index);
                return _SlotTile(
                  label: l10n.formatTimeOfDay(
                    slot,
                    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                      context,
                    ),
                  ),
                  isSelected: index == selectedIndex,
                  onTap: () => widget.onSelected(slot),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// One tappable row of the slot list; the current choice is tinted and checked.
class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? scheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 20, color: scheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}
