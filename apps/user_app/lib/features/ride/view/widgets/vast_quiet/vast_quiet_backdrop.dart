import 'package:flutter/material.dart';

import 'vast_quiet_theme.dart';

/// The entry-point scene: alpenglow-tipped peaks rising from a sea of cloud on
/// a pale paper sky — the Vast Quiet mood, painted rather than photographed.
///
/// It renders purely from [VastQuiet] tokens (paper, ink, alpenglow) so it
/// carries the ride flow's design language onto the landing screen without an
/// image asset. Decorative only: it takes no data and emits no events. Sits
/// behind the trip chooser; its lower half dissolves into cloud and then into
/// [VastQuiet.paper], so content laid over the fade stays legible on the page.
///
/// Gradients — which the cards avoid — are used here deliberately: the warm
/// crest light and the cloud sea are the whole point of the scene.
class VastQuietBackdrop extends StatelessWidget {
  const VastQuietBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _BackdropPainter());
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  // Ridgelines as (x, y) fractions of the paint size. The front ridge is the
  // dark charcoal one nearest the viewer; the back ridge is the hazier, lower
  // range behind it. Both close down the sides to fill below their crests.
  static const List<Offset> _frontRidge = [
    Offset(0.00, 0.60),
    Offset(0.10, 0.50),
    Offset(0.18, 0.55),
    Offset(0.28, 0.40),
    Offset(0.36, 0.46),
    Offset(0.46, 0.20),
    Offset(0.52, 0.14),
    Offset(0.58, 0.26),
    Offset(0.66, 0.34),
    Offset(0.74, 0.28),
    Offset(0.82, 0.40),
    Offset(0.90, 0.36),
    Offset(1.00, 0.48),
  ];

  static const List<Offset> _backRidge = [
    Offset(0.00, 0.66),
    Offset(0.12, 0.58),
    Offset(0.22, 0.62),
    Offset(0.34, 0.50),
    Offset(0.44, 0.56),
    Offset(0.55, 0.44),
    Offset(0.64, 0.52),
    Offset(0.76, 0.46),
    Offset(0.86, 0.54),
    Offset(1.00, 0.50),
  ];

  // Distant range: a light, hazy warm grey. Near range: a warm charcoal.
  static const Color _backFill = Color(0xFFC9C7C4);
  static const Color _frontFill = Color(0xFF56524E);
  // The misty near-white the sky lightens to at the top.
  static const Color _sky = Color(0xFFFBFAF9);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Sky: near-white at the top settling into paper toward the cloud line.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sky, VastQuiet.paper],
        ).createShader(rect),
    );

    // Distant range, then its faint crest light.
    final backPath = _ridgePath(_backRidge, size);
    canvas.drawPath(backPath, Paint()..color = _backFill);
    _paintCrestLight(canvas, size, backPath, strength: 0.30);

    // Near range, then its stronger alpenglow.
    final frontPath = _ridgePath(_frontRidge, size);
    canvas.drawPath(frontPath, Paint()..color = _frontFill);
    _paintCrestLight(canvas, size, frontPath, strength: 0.85);

    // Sea of cloud: rolls up over the mountain bases, thinning to paper so the
    // scene melts seamlessly into the page below it.
    final cloud = Rect.fromLTRB(0, size.height * 0.30, size.width, size.height);
    canvas.drawRect(
      cloud,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFFFFF),
            Color(0xD9FFFFFF),
            VastQuiet.paper,
            VastQuiet.paper,
          ],
          stops: const [0.0, 0.45, 0.85, 1.0],
        ).createShader(cloud),
    );
  }

  /// Builds a filled mountain shape from ridge points: trace the crest, then
  /// drop to the bottom corners and close.
  Path _ridgePath(List<Offset> ridge, Size size) {
    final path = Path()
      ..moveTo(ridge.first.dx * size.width, ridge.first.dy * size.height);
    for (final p in ridge.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    return path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  /// Warms the upper slopes of [ridge] with alpenglow, clipped to the mountain
  /// so the light falls only on the peaks and fades down the faces.
  void _paintCrestLight(
    Canvas canvas,
    Size size,
    Path ridge, {
    required double strength,
  }) {
    canvas.save();
    canvas.clipPath(ridge);
    final glow = Rect.fromLTRB(0, 0, size.width, size.height * 0.5);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            VastQuiet.alpenglow.withValues(alpha: strength),
            VastQuiet.alpenglow.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}
