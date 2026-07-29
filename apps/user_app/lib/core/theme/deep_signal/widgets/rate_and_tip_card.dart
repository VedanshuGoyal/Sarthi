import 'package:flutter/material.dart';

import '../deep_signal_tokens.dart';
import 'deep_signal_card.dart';

/// **Rate & tip.** A post-trip card: a star row and a row of tip chips. Stars
/// are filled with ink and empty in [soft] — never gold. Tip chips are square;
/// the selected one inverts to an ink fill.
///
/// State-free: the parent owns [rating] (1..5, 0 = none) and [selectedTip] and
/// is told of taps via [onRate] / [onTip].
class DeepSignalRateAndTipCard extends StatelessWidget {
  const DeepSignalRateAndTipCard({
    super.key,
    required this.question,
    required this.rating,
    required this.onRate,
    required this.tips,
    required this.selectedTip,
    required this.onTip,
    this.eyebrow = 'Trip complete',
    this.tipLabel = 'Add a tip',
    this.width = 390,
  });

  /// The headline question, e.g. "How was your ride with Marcus?".
  final String question;

  /// The current star rating, 1..5 (0 for none).
  final int rating;
  final ValueChanged<int> onRate;

  /// The tip chip labels, e.g. `['None', '£1', '£2', '£5']`.
  final List<String> tips;
  final int selectedTip;
  final ValueChanged<int> onTip;

  final String eyebrow;
  final String tipLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow.toUpperCase(), style: t.eyebrow()),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
            child: Text(question, style: t.title(24, height: 1.25)),
          ),
          Row(
            children: [
              for (var n = 1; n <= 5; n++)
                Padding(
                  padding: EdgeInsets.only(right: n == 5 ? 0 : 10),
                  child: _Star(filled: n <= rating, onTap: () => onRate(n)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
            child: Text(tipLabel.toUpperCase(), style: t.eyebrow()),
          ),
          Row(
            children: [
              for (var i = 0; i < tips.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == tips.length - 1 ? 0 : 8),
                    child: _TipChip(
                      label: tips[i],
                      selected: i == selectedTip,
                      onTap: () => onTip(i),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
    final t = DeepSignalTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedDefaultTextStyle(
        duration: DeepSignalTokens.motion,
        curve: DeepSignalTokens.easing,
        style: TextStyle(fontSize: 26, height: 1, color: filled ? t.fg : t.soft),
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
    final t = DeepSignalTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: DeepSignalTokens.motion,
        curve: DeepSignalTokens.easing,
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.fg : Colors.transparent,
          borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
          border: Border.all(color: selected ? t.fg : t.soft),
        ),
        child: Text(
          label,
          style: t.mono(
            size: 11,
            color: selected ? t.onFill : t.fg,
            trackingEm: 0.1,
          ),
        ),
      ),
    );
  }
}
