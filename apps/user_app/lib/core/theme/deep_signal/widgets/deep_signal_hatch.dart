import 'package:flutter/material.dart';

/// A flat hatched fill — the design's stand-in "texture" for a photo or a live
/// map, in place of a shadow or gradient. [angle] is the stripe direction in
/// degrees (135 for the diagonal photo tile, 90 for the map's verticals);
/// [band] is the stripe pitch in logical pixels.
///
/// Both tones are passed in so the pattern re-colours per mode, matching the CSS
/// `repeating-linear-gradient` in the source.
class DeepSignalHatch extends StatelessWidget {
  const DeepSignalHatch({
    super.key,
    required this.base,
    required this.stripe,
    this.angle = 135,
    this.band = 5,
    this.child,
  });

  final Color base;
  final Color stripe;
  final double angle;
  final double band;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _HatchPainter(
      angle: angle,
      band: band,
      base: base,
      stripe: stripe,
    ),
    child: child,
  );
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({
    required this.angle,
    required this.band,
    required this.base,
    required this.stripe,
  });

  final double angle;
  final double band;
  final Color base;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final paint = Paint()
      ..color = stripe
      ..style = PaintingStyle.stroke
      ..strokeWidth = band;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Rotate the canvas so vertical lines become the requested angle, then draw
    // lines two bands apart across a diagonal-spanning extent.
    final radians = angle * 3.1415926535 / 180;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(radians);
    final extent = size.width + size.height;
    for (double x = -extent; x < extent; x += band * 2) {
      canvas.drawLine(Offset(x, -extent), Offset(x, extent), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.angle != angle ||
      old.band != band ||
      old.base != base ||
      old.stripe != stripe;
}
