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
      TripType.roundTrip,
      Icons.sync_alt,
      'Round Trip',
      'Hire drivers by the hour for an out-and-back journey.',
    ),
    (
      TripType.multiStop,
      Icons.alt_route,
      'Multi-Stop Trip',
      'One booking that visits several stops in sequence.',
    ),
    (
      TripType.oneWay,
      Icons.arrow_right_alt,
      'One-Way Trip',
      'A single drive from your starting point to a destination.',
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

    final cards = [
      for (final (type, icon, title, subtitle) in _options)
        TripOptionCard(
          icon: icon,
          title: title,
          subtitle: subtitle,
          selected: vm.selectedType == type,
          onTap: () => _select(context, ref, type),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide: cards side-by-side, equal height. Narrow: stacked.
        if (constraints.maxWidth >= _wideBreakpoint) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: card),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(height: 16),
              card,
            ],
          ],
        );
      },
    );
  }
}
