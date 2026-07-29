import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// One saved place in the [SavedPlacesCard].
class SavedPlace {
  const SavedPlace({
    required this.tag,
    required this.name,
    required this.address,
    this.distance = '',
  });

  /// The single lettered glyph in the icon square, e.g. "H", "W", "+".
  final String tag;
  final String name;

  /// Mono address line, e.g. "14 QUEEN'S QUAY, E1".
  final String address;

  /// Optional mono distance on the right, e.g. "0.4 KM".
  final String distance;
}

/// **1f — Saved place.** A list of shortcut rows divided by hairlines. The icon
/// slot is a lettered square (26px), deliberately not a pictogram.
///
/// State-free per the reusable-widget guideline: rows in, taps out via [onTap].
class SavedPlacesCard extends StatelessWidget {
  const SavedPlacesCard({
    super.key,
    required this.places,
    required this.onTap,
    this.width = 390,
  });

  final List<SavedPlace> places;
  final ValueChanged<SavedPlace> onTap;
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
            for (var i = 0; i < places.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i < places.length - 1
                      ? const Border(bottom: VastQuiet.hairlineSide)
                      : null,
                ),
                child: _PlaceRow(
                  place: places[i],
                  onTap: () => onTap(places[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onTap});

  final SavedPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            _TagSquare(tag: place.tag),
            const SizedBox(width: VastQuiet.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name, style: VastQuiet.title(15, height: 1.2)),
                  const SizedBox(height: 2),
                  Text(
                    place.address,
                    style: VastQuiet.mono(
                      color: VastQuiet.ink42,
                      trackingEm: 0.08,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            if (place.distance.isNotEmpty) ...[
              const SizedBox(width: VastQuiet.s8),
              Text(
                place.distance,
                style: VastQuiet.mono(color: VastQuiet.ink35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The 26px lettered icon square.
class _TagSquare extends StatelessWidget {
  const _TagSquare({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: VastQuiet.ink18),
        borderRadius: BorderRadius.circular(VastQuiet.radius),
      ),
      child: Text(tag, style: VastQuiet.mono(size: 9, color: VastQuiet.ink50)),
    );
  }
}
