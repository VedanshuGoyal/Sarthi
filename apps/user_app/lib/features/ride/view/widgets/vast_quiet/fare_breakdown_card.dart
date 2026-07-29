import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// One label/value line of the [FareBreakdownCard].
class FareLine {
  const FareLine({required this.label, required this.value});

  /// Mono line label, e.g. "DISTANCE · 8.1 KM".
  final String label;

  /// The amount, e.g. "£9.72".
  final String value;
}

/// **1d — Fare breakdown.** A total with a mono toggle that reveals the
/// itemised lines. The rows are monospaced so the figures align in a column;
/// the reveal animates its height on the system curve.
///
/// State-free per the reusable-widget guideline: the parent owns [open] and is
/// told of the tap through [onToggle].
class FareBreakdownCard extends StatelessWidget {
  const FareBreakdownCard({
    super.key,
    required this.title,
    required this.date,
    required this.total,
    required this.lines,
    required this.open,
    required this.onToggle,
    this.width = 390,
  });

  /// The mono eyebrow, e.g. "Fare — Plate III".
  final String title;

  /// The mono date on the right, e.g. "2026-07-21".
  final String date;

  /// The headline total, e.g. "£18.40".
  final String total;

  final List<FareLine> lines;

  /// Whether the breakdown is revealed.
  final bool open;
  final VoidCallback onToggle;
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title.toUpperCase(), style: VastQuiet.eyebrow()),
                Text(
                  date,
                  style: VastQuiet.mono(
                    size: 9.5,
                    color: VastQuiet.ink35,
                    trackingEm: 0.12,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(total, style: VastQuiet.display(44)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    open ? 'HIDE BREAKDOWN ↑' : 'SHOW BREAKDOWN ↓',
                    style: VastQuiet.mono(
                      color: VastQuiet.alpenglow,
                      trackingEm: 0.18,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: VastQuiet.motion,
              curve: VastQuiet.easing,
              alignment: Alignment.topCenter,
              child: open
                  ? _Breakdown(lines: lines)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.lines});

  final List<FareLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: VastQuiet.s14),
      padding: const EdgeInsets.only(top: VastQuiet.s14),
      decoration: const BoxDecoration(
        border: Border(top: VastQuiet.hairlineSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 11),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lines[i].label,
                  style: VastQuiet.mono(
                    size: 11,
                    color: VastQuiet.ink60,
                    trackingEm: 0.08,
                  ),
                ),
                Text(
                  lines[i].value,
                  style: VastQuiet.mono(
                    size: 11,
                    color: VastQuiet.ink,
                    trackingEm: 0.08,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
