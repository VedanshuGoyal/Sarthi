import 'package:flutter/material.dart';

import '../deep_signal_tokens.dart';
import 'deep_signal_card.dart';

/// One line in the [DeepSignalFareBreakdownCard].
class FareLine {
  const FareLine({required this.label, required this.value});

  /// The mono label, e.g. "DISTANCE · 8.1 KM".
  final String label;

  /// The formatted amount, e.g. "£9.72".
  final String value;
}

/// **Fare breakdown — collapsed / expanded.** A large Instrument Sans total
/// with a mono toggle that reveals right-aligned fare lines. Rows are mono so
/// the digits column-align.
///
/// State-free: the parent owns [open] and flips it via [onToggle].
class DeepSignalFareBreakdownCard extends StatelessWidget {
  const DeepSignalFareBreakdownCard({
    super.key,
    required this.title,
    required this.date,
    required this.total,
    required this.lines,
    required this.open,
    required this.onToggle,
    this.width = 390,
  });

  /// The eyebrow, e.g. "Fare — Plate III".
  final String title;

  /// The date stamp, e.g. "2026-07-21".
  final String date;

  /// The headline total, e.g. "£18.40".
  final String total;

  final List<FareLine> lines;

  /// Whether the breakdown is expanded.
  final bool open;
  final VoidCallback onToggle;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title.toUpperCase(), style: t.eyebrow()),
              Text(
                date,
                style: t.mono(size: 9.5, color: t.faintest, trackingEm: 0.12),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(total, style: t.display(44)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                open ? 'HIDE BREAKDOWN ↑' : 'SHOW BREAKDOWN ↓',
                style: t.mono(color: t.accent, trackingEm: 0.18),
              ),
            ),
          ),
          AnimatedSize(
            duration: DeepSignalTokens.motion,
            curve: DeepSignalTokens.easing,
            alignment: Alignment.topCenter,
            child: open
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.only(top: 14),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.hairline)),
                    ),
                    child: Column(
                      children: [
                        for (final line in lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  line.label,
                                  style: t.mono(
                                    size: 11,
                                    color: t.fgAlpha(0.6),
                                    trackingEm: 0.08,
                                  ),
                                ),
                                Text(
                                  line.value,
                                  style: t.mono(
                                    size: 11,
                                    color: t.fg,
                                    trackingEm: 0.08,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
