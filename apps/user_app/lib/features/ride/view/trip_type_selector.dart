import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trip_type.dart';
import '../ride_providers.dart';
import 'widgets/trip_option_card.dart';

/// The post-login trip chooser: a tappable option card per [TripType].
///
/// Tapping a card is the whole decision — it highlights the card and fires
/// [onSelected] immediately, with no separate confirm step.
///
/// Embeddable (no [Scaffold] of its own) so the landing screen can pin a
/// greeting above it. It watches [tripSelectionViewModelProvider] and renders
/// the cards side-by-side on wide viewports (tablet/desktop) or stacked on
/// phones, per the responsive-layout guideline.
class TripTypeSelector extends ConsumerWidget {
  const TripTypeSelector({super.key, this.onSelected});

  /// Invoked with the chosen type as soon as a card is tapped. Defaults to a
  /// placeholder confirmation until the booking flow is built.
  final void Function(TripType type)? onSelected;

  /// The breakpoint above which the cards sit side-by-side.
  static const double _wideBreakpoint = 560;

  /// Presentation for each [TripType], in display order.
  static const _options = <(TripType, IconData, String, String)>[
    (
      TripType.oneWay,
      Icons.arrow_forward_rounded,
      'One-Way Trip',
      'Drop at a destination.',
    ),
    (
      TripType.roundTrip,
      Icons.schedule_rounded,
      'Round Trip',
      'Hire a driver by the hour, out and back.',
    ),
    (
      TripType.multiStop,
      Icons.alt_route_rounded,
      'Multi-Stop Trip',
      'Several stops, one driver.',
    ),
  ];

  void _select(BuildContext context, WidgetRef ref, TripType type) {
    ref.read(tripSelectionViewModelProvider).select(type);
    if (onSelected != null) return onSelected!(type);
    // Placeholder until the booking flow exists: confirm the choice so the
    // wiring is verifiable end-to-end.
    final summary = _options.firstWhere((option) => option.$1 == type).$3;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Selected: $summary')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(tripSelectionViewModelProvider);

    TripOptionCard card(
      (TripType, IconData, String, String) option, {
      bool featured = false,
    }) {
      final (type, icon, title, subtitle) = option;
      return TripOptionCard(
        icon: icon,
        title: title,
        subtitle: subtitle,
        featured: featured,
        selected: vm.selectedType == type,
        onTap: () => _select(context, ref, type),
      );
    }

    // Round Trip — hiring by the hour, the core service — leads as the wide
    // featured card; the other two sit side by side beneath it (or all three
    // in one row on wide windows).
    final featured = _options.firstWhere((o) => o.$1 == TripType.roundTrip);
    final others = [
      for (final option in _options)
        if (option.$1 != TripType.roundTrip) option,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: card(featured, featured: true)),
                for (final option in others) ...[
                  const SizedBox(width: 16),
                  Expanded(child: card(option)),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            card(featured, featured: true),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, option) in others.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: card(option)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
