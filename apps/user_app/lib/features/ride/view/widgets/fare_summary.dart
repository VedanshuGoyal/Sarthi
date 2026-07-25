import 'package:flutter/material.dart';

/// A single-line fare readout: a label and hire caption on the left, the amount
/// on the right.
///
/// State-free per the reusable-widget guideline: it renders the [fare] (whole
/// rupees) it is handed for a given number of [hours]; the parent owns the
/// pricing. Before a car type is chosen the parent passes the standard-rate
/// preview, so [approximate] softens the label to "From".
class FareSummary extends StatelessWidget {
  const FareSummary({
    super.key,
    required this.fare,
    required this.hours,
    this.approximate = false,
    this.onDisclaimerTap,
  });

  /// The total fare to show, in whole rupees (night surcharge included).
  final int fare;

  /// How many hours the fare covers — shown as a caption.
  final int hours;

  /// When true the fare is a not-yet-final preview (no car type chosen).
  final bool approximate;

  /// Invoked when the customer taps the fare's `*` marker — the parent shows
  /// the "prices may vary" note. The marker is inert (but still shown) when null.
  final VoidCallback? onDisclaimerTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approximate ? 'Estimated fare from' : 'Estimated fare',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                'for $hours ${hours == 1 ? 'hour' : 'hours'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onDisclaimerTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '₹$fare'),
                  TextSpan(
                    text: ' *',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
