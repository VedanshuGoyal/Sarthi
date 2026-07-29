import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// One past trip in the [TripHistoryCard].
class TripHistoryEntry {
  const TripHistoryEntry({
    required this.date,
    required this.price,
    required this.route,
    required this.meta,
  });

  /// Mono date/time, e.g. "21 JUL · 09:41".
  final String date;

  /// The fare, e.g. "£18.40".
  final String price;

  /// The route line, e.g. "Queen's Quay → Aldgate East".
  final String route;

  /// Mono meta, e.g. "GLIDE QUIET · 22 MIN · 4.96 ★".
  final String meta;
}

/// **1h — Trip history.** Past trips as hairline-divided rows within one card —
/// no card-per-row nesting. Each row pairs a mono date and fare over the route
/// and a mono meta line.
///
/// State-free per the reusable-widget guideline: entries in, optional [onTap].
class TripHistoryCard extends StatelessWidget {
  const TripHistoryCard({
    super.key,
    required this.entries,
    this.onTap,
    this.width = 390,
  });

  final List<TripHistoryEntry> entries;

  /// Optional per-row tap; rows are inert when null.
  final ValueChanged<TripHistoryEntry>? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: VastQuietCard(
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < entries.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i < entries.length - 1
                      ? const Border(bottom: VastQuiet.hairlineSide)
                      : null,
                ),
                child: _HistoryRow(
                  entry: entries[i],
                  onTap: onTap == null ? null : () => onTap!(entries[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onTap});

  final TripHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  entry.date,
                  style: VastQuiet.mono(
                    color: VastQuiet.ink42,
                    trackingEm: 0.16,
                  ),
                ),
                Text(entry.price, style: VastQuiet.title(17, height: 1)),
              ],
            ),
            const SizedBox(height: VastQuiet.s8),
            Text(entry.route, style: VastQuiet.title(15, height: 1.35)),
            const SizedBox(height: 6),
            Text(entry.meta, style: VastQuiet.mono(color: VastQuiet.ink42)),
          ],
        ),
      ),
    );
  }
}
