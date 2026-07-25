import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/one_way_trip.dart';
import '../ride_providers.dart';
import '../view_model/one_way_review_view_model.dart';
import 'widgets/car_options_fields.dart';
import 'widgets/route_summary.dart';

/// The final One-Way step: the estimated trip time for the settled plan.
///
/// Everything in [draft] was chosen on the previous step; this screen echoes
/// it read-only, fetches the route's traffic-aware drive time once for the
/// chosen departure, and lets the customer confirm. Changing any choice means
/// going back — which is what keeps the estimate to a single API call per
/// visit. On confirm the assembled [OneWayTrip] is handed back via
/// [onConfirmed]. State lives in [oneWayReviewViewModelProvider], keyed on the
/// draft; this view only renders it.
class OneWayReviewScreen extends ConsumerWidget {
  const OneWayReviewScreen({super.key, required this.draft, this.onConfirmed});

  final OneWayDraft draft;

  /// Invoked with the assembled trip when the CTA is tapped. Defaults to
  /// popping the screen and returning the trip to the previous route.
  final void Function(BuildContext context, OneWayTrip trip)? onConfirmed;

  void _confirm(BuildContext context, OneWayTrip trip) {
    if (onConfirmed != null) return onConfirmed!(context, trip);
    Navigator.of(context).pop(trip);
  }

  /// The CTA hint while the booking can't be confirmed yet: what's missing.
  String? _ctaHint(OneWayReviewViewModel vm) {
    if (vm.canConfirm) return null;
    if (vm.isEstimatingTravelTime) return 'Checking the trip time…';
    return 'The trip time is needed to book — retry the estimate above.';
  }

  static String _formatEta(Duration eta) {
    final hours = eta.inHours;
    final minutes = eta.inMinutes % Duration.minutesPerHour;
    if (hours == 0) return '$minutes min';
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(oneWayReviewViewModelProvider(draft));
    final theme = Theme.of(context);
    final l10n = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Review trip')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      RouteSummary(
                        startAddress: draft.start.address,
                        destinationAddress: draft.destination.address,
                      ),
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Your plan',
                        subtitle: 'Go back to change any of these.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PlanLine(
                              icon: Icons.calendar_today_outlined,
                              label: 'Starts',
                              value:
                                  '${l10n.formatMediumDate(draft.scheduledAt)}'
                                  ', ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(draft.scheduledAt))}',
                            ),
                            const SizedBox(height: 10),
                            _PlanLine(
                              icon: Icons.directions_car_outlined,
                              label: 'Car',
                              value:
                                  '${CarOptionsFields.carTypeLabel(draft.carType)}'
                                  ' · ${CarOptionsFields.transmissionLabel(draft.transmission)}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Trip time',
                        subtitle: 'Estimated for your chosen start time.',
                        child: _TravelTimeEstimate(
                          isLoading: vm.isEstimatingTravelTime,
                          eta: vm.travelTime,
                          onRetry: vm.estimateFailed ? vm.retryEstimate : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_ctaHint(vm) case final hint?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            hint,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      SarthiPrimaryButton(
                        label: 'Confirm booking',
                        onPressed: vm.canConfirm
                            ? () => _confirm(context, vm.trip!)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The read-only drive-time readout: a progress note while the estimate is
/// fetched, the formatted duration once known, and a retry affordance when the
/// request failed. Pure per the widget guideline — values in, [onRetry] out.
class _TravelTimeEstimate extends StatelessWidget {
  const _TravelTimeEstimate({
    required this.isLoading,
    required this.eta,
    required this.onRetry,
  });

  final bool isLoading;
  final Duration? eta;

  /// Non-null only when the last estimate failed and can be retried.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Widget content;
    if (isLoading) {
      content = Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Checking the drive time…', style: theme.textTheme.bodyMedium),
        ],
      );
    } else if (eta != null) {
      content = Row(
        children: [
          Icon(Icons.schedule, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Text(
            'About ${OneWayReviewScreen._formatEta(eta!)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't get the trip time.",
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SarthiColors.ultramarineWash,
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
      ),
      child: content,
    );
  }
}

/// One read-only line of the settled plan: an icon, a short label, the value.
class _PlanLine extends StatelessWidget {
  const _PlanLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled section: a heading (with optional [subtitle]) above its [child].
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
