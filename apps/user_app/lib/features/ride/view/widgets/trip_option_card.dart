import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// A selectable card presenting one trip option (icon, title, blurb).
///
/// State-free per the reusable-widget guideline: it renders whether it is
/// [selected] and emits [onTap]; the parent owns the selection. When picked it
/// adopts the brand tint and border and shows a confirming checkmark.
class TripOptionCard extends StatelessWidget {
  const TripOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Selected cards pick up the brand colour; unselected stay neutral.
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    final background = selected ? SarthiColors.ultramarineWash : scheme.surface;
    final iconColor = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(SarthiTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SarthiTheme.radius),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // A checkmark confirms the active choice.
                  if (selected)
                    Icon(Icons.check_circle, color: scheme.primary, size: 22),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
