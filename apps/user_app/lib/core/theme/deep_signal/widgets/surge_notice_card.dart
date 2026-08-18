import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'deep_signal_card.dart';

/// **Surge / unavailable.** A demand notice: an accent eyebrow, a headline, an
/// estimate, and accept/wait actions. The alert reads as an accent *hairline
/// border* — never a tinted fill.
///
/// State-free: the two actions out via [onAccept] / [onWait].
class DeepSignalSurgeNoticeCard extends StatelessWidget {
  const DeepSignalSurgeNoticeCard({
    super.key,
    required this.message,
    required this.estimate,
    required this.onAccept,
    required this.onWait,
    this.eyebrow = 'Demand notice',
    this.acceptLabel = 'Accept fare',
    this.waitLabel = 'Wait',
    this.width = 390,
  });

  /// The headline, e.g. "Fares in this area are 1.6× until 21:30.".
  final String message;

  /// The estimate line, e.g. "Estimated £18.40 → £29.44".
  final String estimate;

  final VoidCallback onAccept;
  final VoidCallback onWait;

  final String eyebrow;
  final String acceptLabel;
  final String waitLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      border: Border.all(color: t.accentBorder),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow.toUpperCase(), style: t.eyebrow(color: t.accent)),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 12),
            child: Text(message, style: t.title(22, height: 1.3)),
          ),
          Text(
            estimate,
            style: t.mono(
              size: 11,
              color: t.muted,
              trackingEm: 0.04,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  child: Text(acceptLabel.toUpperCase()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onWait,
                  child: Text(waitLabel.toUpperCase()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
