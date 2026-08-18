import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'deep_signal_card.dart';

/// One completed trip in the [DeepSignalTripHistoryCard].
class TripHistoryEntry {
  const TripHistoryEntry({
    required this.date,
    required this.price,
    required this.route,
    required this.meta,
  });

  /// The mono date/time, e.g. "21 JUL · 09:41".
  final String date;

  /// The fare, e.g. "£18.40".
  final String price;

  /// The route line, e.g. "Queen's Quay → Aldgate East".
  final String route;

  /// The mono meta, e.g. "GLIDE QUIET · 22 MIN · 4.96 ★".
  final String meta;
}

/// **Trip history row.** A list card of past trips, rows divided by hairlines
/// only — no card-per-row nesting.
class DeepSignalTripHistoryCard extends StatelessWidget {
  const DeepSignalTripHistoryCard({
    super.key,
    required this.entries,
    this.onTap,
    this.width = 390,
  });

  final List<TripHistoryEntry> entries;

  /// Optional per-row tap, reported by index.
  final ValueChanged<int>? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i < entries.length - 1
                    ? Border(bottom: BorderSide(color: t.hairline))
                    : null,
              ),
              child: InkWell(
                onTap: onTap == null ? null : () => onTap!(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            entries[i].date,
                            style: t.mono(
                              size: 9.5,
                              color: t.faint,
                              trackingEm: 0.16,
                            ),
                          ),
                          Text(entries[i].price, style: t.title(17, height: 1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(entries[i].route, style: t.title(15, height: 1.35)),
                      const SizedBox(height: 6),
                      Text(
                        entries[i].meta,
                        style: t.mono(color: t.fgAlpha(t.isDark ? 0.4 : 0.4)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
