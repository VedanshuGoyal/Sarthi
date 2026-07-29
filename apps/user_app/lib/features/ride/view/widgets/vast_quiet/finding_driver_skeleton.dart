import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// **1i — Loading skeleton.** The "finding a driver" placeholder: three bars
/// that breathe on an opacity shimmer (1.8s, staggered) — no sliding sheen, no
/// pulse scale — over a mono search caption.
///
/// The data ([heading], [caption]) is state-free; the shimmer is the only
/// internal state.
class FindingDriverSkeleton extends StatefulWidget {
  const FindingDriverSkeleton({
    super.key,
    this.heading = 'Finding a driver',
    this.caption = 'Searching 12 vehicles nearby',
    this.width = 390,
  });

  final String heading;
  final String caption;
  final double width;

  @override
  State<FindingDriverSkeleton> createState() => _FindingDriverSkeletonState();
}

class _FindingDriverSkeletonState extends State<FindingDriverSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  // The three bars, as (width fraction, stagger fraction of the period).
  static const _bars = [(0.62, 0.0), (0.88, 0.111), (0.40, 0.222)];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: VastQuietCard(
        padding: const EdgeInsets.all(VastQuiet.s22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.heading.toUpperCase(),
              style: VastQuiet.eyebrow(color: VastQuiet.ink35),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _bars.length; i++) ...[
                    if (i > 0) const SizedBox(height: VastQuiet.s14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _bars[i].$1,
                        child: Opacity(
                          opacity: _shimmer(_bars[i].$2),
                          child: Container(
                            height: 14,
                            color: const Color(0xFFECEAE7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: VastQuiet.s22),
              child: VastQuietDivider(),
            ),
            Padding(
              padding: const EdgeInsets.only(top: VastQuiet.s14),
              child: Text(
                widget.caption.toUpperCase(),
                style: VastQuiet.mono(
                  color: VastQuiet.ink35,
                  trackingEm: 0.12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opacity for a bar delayed by [phase] of the period: a cosine between the
  /// design's .35 and .7 bounds.
  double _shimmer(double phase) {
    final t = (_controller.value - phase) % 1.0;
    final factor = (1 - math.cos(2 * math.pi * t)) / 2; // 0..1
    return 0.35 + 0.35 * factor;
  }
}
