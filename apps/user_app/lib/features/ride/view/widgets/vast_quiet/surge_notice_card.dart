import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// **1j — Surge / unavailable.** A demand notice. The alert reads through an
/// alpenglow hairline border and accent eyebrow — never a tinted fill — with an
/// accept / wait choice below.
///
/// State-free per the reusable-widget guideline: copy in, the two actions out.
class SurgeNoticeCard extends StatelessWidget {
  const SurgeNoticeCard({
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

  /// The mono estimate line, e.g. "Estimated £18.40 → £29.44".
  final String estimate;

  final VoidCallback onAccept;
  final VoidCallback onWait;

  final String eyebrow;
  final String acceptLabel;
  final String waitLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: VastQuietCard(
        border: Border.all(color: VastQuiet.alpenglowHairline),
        padding: const EdgeInsets.all(VastQuiet.s22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: VastQuiet.eyebrow(color: VastQuiet.alpenglow),
            ),
            const SizedBox(height: VastQuiet.s14),
            Text(message, style: VastQuiet.title(22, height: 1.3)),
            const SizedBox(height: 12),
            Text(
              estimate,
              style: VastQuiet.mono(
                size: 11,
                color: VastQuiet.ink60,
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
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(acceptLabel.toUpperCase()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onWait,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(waitLabel.toUpperCase()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
