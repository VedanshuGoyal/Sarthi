import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// Picks how many hours to hire a driver for: a −/＋ stepper plus quick-pick
/// chips for the common durations.
///
/// State-free per the reusable-widget guideline: it renders [hours] and emits
/// intents ([onDecrement], [onIncrement], [onQuickPick]); the parent (view
/// model) owns the value and the bounds.
class HoursSelector extends StatelessWidget {
  const HoursSelector({
    super.key,
    required this.hours,
    required this.quickHours,
    required this.canDecrement,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
    required this.onQuickPick,
  });

  final int hours;
  final List<int> quickHours;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<int> onQuickPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(Skyline.radius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              _StepButton(
                icon: Icons.remove,
                tooltip: 'Fewer hours',
                onPressed: canDecrement ? onDecrement : null,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$hours',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hours == 1 ? 'hour' : 'hours',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _StepButton(
                icon: Icons.add,
                tooltip: 'More hours',
                onPressed: canIncrement ? onIncrement : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final value in quickHours) ...[
                if (value != quickHours.first) const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('${value}h'),
                  selected: hours == value,
                  onSelected: (_) => onQuickPick(value),
                  showCheckmark: false,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A round, bordered +/− button that disables (dims) when [onPressed] is null.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final enabled = onPressed != null;
    // A soft tinted square rather than an outlined ring — Skyline's stepper.
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: enabled ? t.primarySoft : t.sunken,
        foregroundColor: enabled ? t.primaryText : t.inkFaint,
        disabledBackgroundColor: t.sunken,
        disabledForegroundColor: t.inkFaint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radiusSm),
        ),
      ),
    );
  }
}
