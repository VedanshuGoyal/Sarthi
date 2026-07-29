import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// One selectable ride class in the [RideClassPicker].
class RideClassOption {
  const RideClassOption({
    required this.id,
    required this.name,
    required this.meta,
    required this.price,
    required this.note,
  });

  /// Stable identity used for selection.
  final String id;

  /// The service name, e.g. "Glide Quiet".
  final String name;

  /// Mono sub-line, e.g. "4 SEATS · 5 MIN".
  final String meta;

  /// The formatted price, e.g. "£18.40".
  final String price;

  /// Mono price note, e.g. "NO SMALL TALK".
  final String note;
}

/// **1a — Ride class picker.** A card of selectable service rows with a confirm
/// action. The chosen row takes a 1px ink border and a filled alpenglow marker;
/// the rest sit flush, divided by hairlines.
///
/// State-free per the reusable-widget guideline: the parent owns [selectedId]
/// and is told of taps through [onSelect] / [onConfirm].
class RideClassPicker extends StatelessWidget {
  const RideClassPicker({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelect,
    required this.onConfirm,
    this.plateLabel = 'Plate I — Service',
    this.width = 390,
  });

  final List<RideClassOption> options;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onConfirm;

  /// The mono eyebrow at the card's top-left.
  final String plateLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (o) => o.id == selectedId,
      orElse: () => options.first,
    );

    return SizedBox(
      width: width,
      child: VastQuietCard(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(plateLabel.toUpperCase(), style: VastQuiet.eyebrow()),
                Text(
                  '${options.length} AVAILABLE',
                  style: VastQuiet.mono(
                    size: 9.5,
                    color: VastQuiet.ink35,
                    trackingEm: 0.14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VastQuiet.s14 + 4),
            for (final option in options)
              _OptionRow(
                option: option,
                selected: option.id == selectedId,
                onTap: () => onSelect(option.id),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onConfirm,
              child: Text('CONFIRM ${selected.name.toUpperCase()}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single 66px option row. Animated so selection glides on the system curve.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final RideClassOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: VastQuiet.motion,
        curve: VastQuiet.easing,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: VastQuiet.s14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VastQuiet.radius),
          border: Border.all(
            color: selected ? VastQuiet.ink : Colors.transparent,
          ),
          // Unselected rows are separated by a bottom hairline instead.
          boxShadow: null,
        ),
        foregroundDecoration: selected
            ? null
            : const BoxDecoration(
                border: Border(bottom: VastQuiet.hairlineSide),
              ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _Marker(selected: selected),
                  const SizedBox(width: VastQuiet.s14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VastQuiet.title(17, height: 1.1),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          option.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VastQuiet.mono(color: VastQuiet.ink45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(option.price, style: VastQuiet.title(18, height: 1)),
                const SizedBox(height: 3),
                Text(
                  option.note,
                  style: VastQuiet.mono(color: VastQuiet.ink35),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The 9px selection square: filled alpenglow when active, a hairline outline
/// when idle.
class _Marker extends StatelessWidget {
  const _Marker({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: VastQuiet.motion,
      curve: VastQuiet.easing,
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: selected ? VastQuiet.alpenglow : Colors.transparent,
        borderRadius: BorderRadius.circular(1),
        border: Border.all(
          color: selected ? VastQuiet.alpenglow : VastQuiet.ink28,
        ),
      ),
    );
  }
}
