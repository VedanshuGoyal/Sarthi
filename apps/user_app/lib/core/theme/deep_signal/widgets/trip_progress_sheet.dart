import 'package:flutter/material.dart';

import '../deep_signal_tokens.dart';
import 'deep_signal_card.dart';
import 'deep_signal_hatch.dart';

/// **Trip in progress — map sheet.** A live-route header over the arrival
/// readout: a big Instrument Sans "arriving" figure, remaining distance / ETA,
/// and a 1px progress *rail* (not a bar) with an accent fill and a square dot.
///
/// State-free: pass a [progress] in `0..1` and the labels; a hatched panel
/// stands in for the map unless a [map] widget is supplied.
class DeepSignalTripProgressSheet extends StatelessWidget {
  const DeepSignalTripProgressSheet({
    super.key,
    required this.arriving,
    required this.remaining,
    required this.eta,
    required this.progress,
    required this.from,
    required this.to,
    this.coordinates,
    this.map,
    this.width = 390,
  });

  /// The arrival figure, e.g. "6 min".
  final String arriving;

  /// Distance remaining, e.g. "2.4 KM REMAINING".
  final String remaining;

  /// The ETA line, e.g. "ETA 09:41".
  final String eta;

  /// Route completion in `0..1`.
  final double progress;

  final String from;
  final String to;

  /// Optional coordinate overlay for the map header.
  final String? coordinates;

  /// An optional live map; a hatched panel stands in when null.
  final Widget? map;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final clamped = progress.clamp(0.0, 1.0);
    return DeepSignalCard(
      width: width,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.hairline)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  map ??
                      DeepSignalHatch(
                        base: t.surface,
                        stripe: t.raised,
                        angle: 90,
                        band: 7,
                        child: Center(
                          child: Text(
                            'MAP — LIVE ROUTE',
                            style: t.mono(color: t.faint, trackingEm: 0.2),
                          ),
                        ),
                      ),
                  if (coordinates != null)
                    Positioned(
                      left: 18,
                      top: 16,
                      child: Text(
                        coordinates!,
                        style: t.mono(
                          color: t.muted,
                          trackingEm: 0.12,
                          height: 1.8,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
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
                          Text('ARRIVING', style: t.eyebrow()),
                          const SizedBox(height: 8),
                          Text(arriving, style: t.display(40)),
                        ],
                      ),
                    ),
                    Text(
                      '$remaining\n$eta',
                      textAlign: TextAlign.right,
                      style: t.mono(color: t.muted, trackingEm: 0.1, height: 1.8),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ProgressRail(progress: clamped),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      from.toUpperCase(),
                      style: t.mono(color: t.faint, trackingEm: 0.12),
                    ),
                    Text(
                      to.toUpperCase(),
                      style: t.mono(color: t.faint, trackingEm: 0.12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 1px hairline rail with an accent fill and a 7px square progress dot.
class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 7,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Container(height: 1, width: width, color: t.hairline),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: AnimatedContainer(
                  duration: DeepSignalTokens.motion,
                  curve: DeepSignalTokens.easing,
                  height: 1,
                  width: width * progress,
                  color: t.accent,
                ),
              ),
              AnimatedPositioned(
                duration: DeepSignalTokens.motion,
                curve: DeepSignalTokens.easing,
                left: (width * progress - 3.5).clamp(0.0, width - 7),
                top: -3,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
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
