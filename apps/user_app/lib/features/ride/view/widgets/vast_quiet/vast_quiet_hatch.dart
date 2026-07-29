import 'package:flutter/material.dart';

import 'vast_quiet_theme.dart';

/// A flat hatched fill — the design's stand-in "texture" for a photo or a live
/// map, in place of a shadow or gradient. [angle] is the stripe direction in
/// degrees (135 for the diagonal photo tile, 90 for the map's verticals);
/// [band] is the stripe pitch in logical pixels.
///
/// Painted with a repeating two-tone pattern between [VastQuiet.paper] and
/// [dark], matching the CSS `repeating-linear-gradient` in the source.
class VastQuietHatch extends StatelessWidget {
  const VastQuietHatch({
    super.key,
    this.angle = 135,
    this.band = 5,
    this.dark = const Color(0xFFE6E4E1),
    this.child,
  });

  final double angle;
  final double band;
  final Color dark;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HatchPainter(angle: angle, band: band, dark: dark),
      child: child,
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.angle, required this.band, required this.dark});

  final double angle;
  final double band;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = VastQuiet.paper);

    final stripe = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = band;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Rotate the canvas so a set of vertical lines becomes the requested angle,
    // then draw lines two bands apart across a diagonal-spanning extent.
    final radians = angle * 3.1415926535 / 180;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(radians);
    final extent = size.width + size.height;
    for (double x = -extent; x < extent; x += band * 2) {
      canvas.drawLine(Offset(x, -extent), Offset(x, extent), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.angle != angle || old.band != band || old.dark != dark;
}
