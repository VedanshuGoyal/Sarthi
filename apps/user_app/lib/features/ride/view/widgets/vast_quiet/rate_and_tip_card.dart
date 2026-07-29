import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// **1e — Rate & tip.** The post-trip card: a star rating and a row of tip
/// chips. Stars are ink when filled and a faint ink when empty — never gold;
/// the selected tip chip inverts to a solid ink fill.
///
/// State-free per the reusable-widget guideline: [rating] and [selectedTip]
/// are owned by the parent, which hears taps through [onRate] / [onTip].
class RateAndTipCard extends StatelessWidget {
  const RateAndTipCard({
    super.key,
    required this.question,
    required this.rating,
    required this.onRate,
    required this.tips,
    required this.selectedTip,
    required this.onTip,
    this.heading = 'Trip complete',
    this.tipPrompt = 'Add a tip',
    this.width = 390,
  });

  /// The headline question, e.g. "How was your ride with Marcus?".
  final String question;

  /// Stars filled, 0..5.
  final int rating;
  final ValueChanged<int> onRate;

  /// The tip chip labels, e.g. ["None", "£1", "£2", "£5"].
  final List<String> tips;

  /// Index of the chosen chip, or -1 for none.
  final int selectedTip;
  final ValueChanged<int> onTip;

  final String heading;
  final String tipPrompt;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: VastQuietCard(
        padding: const EdgeInsets.all(VastQuiet.s22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(heading.toUpperCase(), style: VastQuiet.eyebrow()),
            const SizedBox(height: VastQuiet.s14),
            Text(question, style: VastQuiet.title(24, height: 1.25)),
            const SizedBox(height: 18),
            Row(
              children: [
                for (var n = 1; n <= 5; n++) ...[
                  if (n > 1) const SizedBox(width: 10),
                  _Star(filled: n <= rating, onTap: () => onRate(n)),
                ],
              ],
            ),
            const SizedBox(height: VastQuiet.s22),
            Text(tipPrompt.toUpperCase(), style: VastQuiet.eyebrow()),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < tips.length; i++) ...[
                  if (i > 0) const SizedBox(width: VastQuiet.s8),
                  Expanded(
                    child: _TipChip(
                      label: tips[i],
                      selected: i == selectedTip,
                      onTap: () => onTip(i),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.filled, required this.onTap});

  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedDefaultTextStyle(
        duration: VastQuiet.motion,
        curve: VastQuiet.easing,
        style: TextStyle(
          fontSize: 26,
          height: 1,
          color: filled ? VastQuiet.ink : VastQuiet.ink18,
        ),
        child: const Text('★'),
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? VastQuiet.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(VastQuiet.radius),
          border: Border.all(
            color: selected ? VastQuiet.ink : VastQuiet.ink18,
          ),
        ),
        child: Text(
          label,
          style: VastQuiet.mono(
            size: 11,
            color: selected ? VastQuiet.onInk : VastQuiet.ink,
          ),
        ),
      ),
    );
  }
}
