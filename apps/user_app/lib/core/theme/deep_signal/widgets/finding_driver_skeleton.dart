import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'deep_signal_card.dart';

/// **Loading skeleton.** The "finding a driver" placeholder: three shimmer bars
/// on a staggered opacity loop (1.8s, no sliding sheen, no pulse scale) over a
/// hairline and a mono caption.
class DeepSignalFindingDriverSkeleton extends StatefulWidget {
  const DeepSignalFindingDriverSkeleton({
    super.key,
    this.eyebrow = 'Finding a driver',
    this.caption = 'Searching 12 vehicles nearby',
    this.width = 390,
  });

  final String eyebrow;
  final String caption;
  final double width;

  @override
  State<DeepSignalFindingDriverSkeleton> createState() =>
      _DeepSignalFindingDriverSkeletonState();
}

class _DeepSignalFindingDriverSkeletonState
    extends State<DeepSignalFindingDriverSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: widget.width,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.eyebrow.toUpperCase(),
            style: t.eyebrow(color: t.faintest),
          ),
          const SizedBox(height: 20),
          _Bar(controller: _controller, widthFactor: 0.62, delay: 0.0),
          const SizedBox(height: DeepSignalTokens.s14),
          _Bar(controller: _controller, widthFactor: 0.88, delay: 0.11),
          const SizedBox(height: DeepSignalTokens.s14),
          _Bar(controller: _controller, widthFactor: 0.40, delay: 0.22),
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Container(height: 1, color: t.hairline),
          ),
          Padding(
            padding: const EdgeInsets.only(top: DeepSignalTokens.s14),
            child: Text(
              widget.caption.toUpperCase(),
              style: t.mono(color: t.faintest, trackingEm: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// One 14px shimmer bar. Its opacity oscillates .35 → .7 → .35 with a phase
/// [delay] so the three bars ripple.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.controller,
    required this.widthFactor,
    required this.delay,
  });

  final AnimationController controller;
  final double widthFactor;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            // Phase-shifted triangle wave between .35 and .7.
            final phase = (controller.value + delay) % 1.0;
            final tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            final opacity = 0.35 + tri * 0.35;
            return Opacity(opacity: opacity, child: child);
          },
          child: Container(height: 14, color: t.skeleton),
        ),
      ),
    );
  }
}
