import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// Two tappable fields — date and time — for choosing when a trip starts.
///
/// State-free per the reusable-widget guideline: it renders the current
/// [scheduledAt] (or a "Select" placeholder) and emits [onTapDate]/[onTapTime];
/// the parent owns the pickers and the resulting value. Dates/times are
/// formatted through [MaterialLocalizations] so they follow the device locale
/// without pulling in `intl`.
class ScheduleField extends StatelessWidget {
  const ScheduleField({
    super.key,
    required this.scheduledAt,
    required this.onTapDate,
    required this.onTapTime,
  });

  final DateTime? scheduledAt;
  final VoidCallback onTapDate;
  final VoidCallback onTapTime;

  /// Swaps just the date of [current] (keeping its time), and vice-versa, so a
  /// parent's date picker leaves the chosen time intact and its time picker
  /// leaves the date. Here so every screen hosting this field combines picker
  /// results the same way.
  static DateTime withDate(DateTime current, DateTime date) =>
      DateTime(date.year, date.month, date.day, current.hour, current.minute);

  static DateTime withTime(DateTime current, TimeOfDay time) => DateTime(
    current.year,
    current.month,
    current.day,
    time.hour,
    time.minute,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final when = scheduledAt;

    final dateLabel = when == null
        ? 'Select date'
        : l10n.formatMediumDate(when);
    final timeLabel = when == null
        ? 'Select time'
        : l10n.formatTimeOfDay(TimeOfDay.fromDateTime(when));

    return Row(
      children: [
        Expanded(
          child: _SlotField(
            icon: Icons.calendar_today_outlined,
            value: dateLabel,
            isPlaceholder: when == null,
            onTap: onTapDate,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SlotField(
            icon: Icons.schedule_outlined,
            value: timeLabel,
            isPlaceholder: when == null,
            onTap: onTapTime,
          ),
        ),
      ],
    );
  }
}

/// A single bordered, tappable field showing an [icon] and its [value].
class _SlotField extends StatelessWidget {
  const _SlotField({
    required this.icon,
    required this.value,
    required this.isPlaceholder,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final bool isPlaceholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textColor = isPlaceholder
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

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
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: textColor,
                    fontWeight: isPlaceholder
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
