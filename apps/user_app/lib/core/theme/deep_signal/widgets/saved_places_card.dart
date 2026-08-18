import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'deep_signal_card.dart';

/// One saved place in the [DeepSignalSavedPlacesCard].
class SavedPlace {
  const SavedPlace({
    required this.tag,
    required this.name,
    required this.address,
    this.distance = '',
  });

  /// The single-letter slot label, e.g. "H", "W", "+".
  final String tag;
  final String name;

  /// The mono address line, e.g. "14 QUEEN'S QUAY, E1".
  final String address;

  /// The mono distance, e.g. "0.4 KM" (may be empty).
  final String distance;
}

/// **Saved place.** A list card of shortcut rows; each has a lettered square
/// slot (not a pictogram), a name, an address, and a distance. Rows are divided
/// by hairlines with no per-row nesting.
///
/// State-free: taps are reported by place [SavedPlace.tag]-keyed id via [onTap].
class DeepSignalSavedPlacesCard extends StatelessWidget {
  const DeepSignalSavedPlacesCard({
    super.key,
    required this.places,
    required this.onTap,
    this.width = 390,
  });

  final List<SavedPlace> places;

  /// Called with the tapped place's index.
  final ValueChanged<int> onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < places.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i < places.length - 1
                    ? Border(bottom: BorderSide(color: t.hairline))
                    : null,
              ),
              child: InkWell(
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: t.soft),
                          borderRadius: BorderRadius.circular(
                            DeepSignalTokens.radius,
                          ),
                        ),
                        child: Text(
                          places[i].tag,
                          style: t.mono(size: 9, color: t.muted),
                        ),
                      ),
                      const SizedBox(width: DeepSignalTokens.s14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              places[i].name,
                              style: t.title(15, height: 1.2),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              places[i].address,
                              style: t.mono(
                                color: t.faint,
                                trackingEm: 0.08,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (places[i].distance.isNotEmpty)
                        Text(
                          places[i].distance,
                          style: t.mono(color: t.faintest),
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
