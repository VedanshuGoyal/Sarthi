import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/trip_type.dart';
import '../ride_providers.dart';
import '../view_model/trip_selection_view_model.dart';
import 'widgets/trip_option_card.dart';

/// The post-login trip chooser: two selectable option cards plus a CTA.
///
/// Embeddable (no [Scaffold] of its own) so the landing screen can pin a
/// greeting above it. It watches [tripSelectionViewModelProvider] and renders
/// the cards side-by-side on wide viewports (tablet/desktop) or stacked on
/// phones, per the responsive-layout guideline.
class TripTypeSelector extends ConsumerWidget {
  const TripTypeSelector({super.key, this.onContinue});

  /// Invoked with the confirmed selection when the CTA is tapped. Defaults to a
  /// placeholder confirmation until the booking flow is built.
  final void Function(TripSelectionViewModel vm)? onContinue;

  /// The breakpoint above which the two cards sit side-by-side.
  static const double _wideBreakpoint = 560;

  void _continue(BuildContext context, TripSelectionViewModel vm) {
    if (onContinue != null) return onContinue!(vm);
    // Placeholder until the booking flow exists: confirm the choice so the
    // wiring is verifiable end-to-end.
    final summary = switch (vm.selectedType!) {
      TripType.roundTrip => 'Round Trip',
      TripType.multiStop => 'Multi-Stop Trip',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Selected: $summary')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(tripSelectionViewModelProvider);

    final roundTrip = TripOptionCard(
      icon: Icons.sync_alt,
      title: 'Round Trip',
      subtitle: 'Hire drivers by the hour for an out-and-back journey.',
      selected: vm.selectedType == TripType.roundTrip,
      onTap: () => vm.select(TripType.roundTrip),
    );

    final multiStop = TripOptionCard(
      icon: Icons.alt_route,
      title: 'Multi-Stop Trip',
      subtitle: 'One booking that visits several stops in sequence.',
      selected: vm.selectedType == TripType.multiStop,
      onTap: () => vm.select(TripType.multiStop),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Wide: cards side-by-side, equal height. Narrow: stacked.
            if (constraints.maxWidth >= _wideBreakpoint) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: roundTrip),
                    const SizedBox(width: 16),
                    Expanded(child: multiStop),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                roundTrip,
                const SizedBox(height: 16),
                multiStop,
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        SarthiPrimaryButton(
          label: 'Continue',
          onPressed: vm.hasSelection ? () => _continue(context, vm) : null,
        ),
      ],
    );
  }
}
