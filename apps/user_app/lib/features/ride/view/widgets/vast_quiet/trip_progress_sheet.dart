import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_hatch.dart';
import 'vast_quiet_theme.dart';

/// **1c — Trip in progress.** A map header over a live-route readout: the
/// arriving figure, remaining distance/ETA, and a hairline progress rail (an
/// alpenglow fill with a square dot) between the two endpoints.
///
/// State-free per the reusable-widget guideline: the map is a [mapChild] slot
/// (a real map view in the app, a hatch in previews) and every value is passed
/// in. [progress] is a 0..1 fraction of the route completed.
class TripProgressSheet extends StatelessWidget {
  const TripProgressSheet({
    super.key,
    required this.arriving,
    required this.remaining,
    required this.eta,
    required this.progress,
    required this.from,
    required this.to,
    this.coordinates,
    this.mapChild,
    this.width = 390,
  });

  /// The headline figure, e.g. "6 min".
  final String arriving;

  /// Right-column top line, e.g. "2.4 KM REMAINING".
  final String remaining;

  /// Right-column bottom line, e.g. "ETA 09:41".
  final String eta;

  /// Fraction of the route completed, 0..1.
  final double progress;

  /// Endpoint labels under the rail.
  final String from;
  final String to;

  /// Optional coordinate overlay on the map, e.g. "57.9097° N\n5.2107° W".
  final String? coordinates;

  /// The map surface; a hatched placeholder is used when null.
  final Widget? mapChild;
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
            _MapHeader(coordinates: coordinates, child: mapChild),
            Padding(
              padding: const EdgeInsets.all(VastQuiet.s22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ARRIVING', style: VastQuiet.eyebrow()),
                            const SizedBox(height: VastQuiet.s8),
                            Text(arriving, style: VastQuiet.display(40)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            remaining,
                            style: VastQuiet.mono(
                              color: VastQuiet.ink50,
                              height: 1.8,
                            ),
                          ),
                          Text(
                            eta,
                            style: VastQuiet.mono(
                              color: VastQuiet.ink50,
                              height: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _ProgressRail(progress: progress.clamp(0, 1)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        from.toUpperCase(),
                        style: VastQuiet.mono(
                          color: VastQuiet.ink42,
                          trackingEm: 0.12,
                        ),
                      ),
                      Text(
                        to.toUpperCase(),
                        style: VastQuiet.mono(
                          color: VastQuiet.ink42,
                          trackingEm: 0.12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.coordinates, required this.child});

  final String? coordinates;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: VastQuiet.hairlineSide),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child ??
                VastQuietHatch(
                  angle: 90,
                  band: 3.5,
                  dark: const Color(0xFFE7E5E1),
                  child: Center(
                    child: Text(
                      'MAP — LIVE ROUTE',
                      style: VastQuiet.eyebrow(color: VastQuiet.ink42),
                    ),
                  ),
                ),
            if (coordinates != null)
              Positioned(
                left: 18,
                top: 16,
                child: Text(
                  coordinates!,
                  style: VastQuiet.mono(
                    color: VastQuiet.ink50,
                    trackingEm: 0.12,
                    height: 1.8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The 1px hairline route rail: an alpenglow fill to [progress] with a small
/// square dot at the head. A rail, deliberately not a bar.
class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filled = constraints.maxWidth * progress;
        return SizedBox(
          height: 7,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Align(
                alignment: Alignment.topLeft,
                child: VastQuietDivider(),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  height: 1,
                  width: filled,
                  color: VastQuiet.alpenglow,
                ),
              ),
              Positioned(
                left: (filled - 3.5).clamp(0.0, constraints.maxWidth - 7),
                top: -3,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: VastQuiet.alpenglow,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
