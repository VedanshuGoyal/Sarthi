/// The MOJUD identity, drawn rather than imported.
///
/// The monogram is six strokes and a dot, and the wordmark is a normalised
/// outline (see `mojud_wordmark_path.dart`), so both are painted at the exact
/// device resolution they are laid out at — no raster asset, no density
/// buckets, no blurry logo on a 3x screen. Painting also lets the ink follow
/// the Deep Signal foreground while the gold signal dot stays constant, which a
/// flat image could not do across the light/dark toggle.
///
/// Every widget here sizes from its constraints (or an explicit [height]) and
/// preserves the mark's aspect, so they can be dropped into any layout.
library;

import 'package:flutter/widgets.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'mojud_brand.dart';
import 'mojud_wordmark_path.dart';

// --- Monogram geometry, in the source SVG's own units -----------------------
//
// Straight from `logo/mojud-icon.svg`: two verticals at x = 16 / 76 crossed by
// four diagonals between y = 16 / 66 / 116, with the signal dot at the centre.
// Keeping the raw numbers here (rather than pre-normalised decimals) means a
// brand-file change can be checked against this file line by line.

const double _strokeWidth = 7;
const double _left = 16;
const double _right = 76;
const double _top = 16;
const double _middle = 66;
const double _bottom = 116;
const double _dotRadius = 5.5;
const double _dotCentreX = 46;

/// Round caps push the drawn mark half a stroke past its geometry on each side.
const double _overhang = _strokeWidth / 2;
const double _markWidth = (_right - _left) + _strokeWidth;
const double _markHeight = (_bottom - _top) + _strokeWidth;

/// Width ÷ height of the monogram including its stroke overhang.
const double kMojudMarkAspect = _markWidth / _markHeight;

// --- Lockup metrics, expressed in monogram heights --------------------------
//
// Derived from `logo/mojud-logo-mono.svg`, where the mark and wordmark sit in
// one coordinate space. Expressing them relative to the mark's height keeps the
// lockup's proportions locked to the brand file at any size.

/// Space between the monogram and the wordmark in the horizontal lockup,
/// measured from `logo/mojud-logo-mono.svg`.
const double _horizontalGap = 0.417850;

/// The same gap in the stacked lockup, measured from
/// `logo/mojud-logo-stacked.svg`. The two lockups do not share a gap — stacked
/// sets much tighter — so each carries its own measured value.
const double _stackedGap = 0.231589;

/// The wordmark's cap height as a fraction of the monogram's height. Identical
/// in both lockups.
const double _wordmarkScale = 0.601402;

/// The MOJUD monogram — six strokes around a gold signal dot.
///
/// [inkColor] defaults to the Deep Signal foreground so the mark reads as part
/// of the page in either mode; [accentColor] defaults to the constant brand
/// gold. Pass [height] for an intrinsic size, or leave it null to fill the
/// available width at the mark's aspect ratio.
class MojudMark extends StatelessWidget {
  const MojudMark({super.key, this.height, this.inkColor, this.accentColor});

  /// The mark's height. When null the mark expands to its constraints.
  final double? height;

  /// The stroke colour. Defaults to [DeepSignalTokens.fg].
  final Color? inkColor;

  /// The signal dot's colour. Defaults to [MojudBrand.gold].
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final painter = _MarkPainter(
      ink: inkColor ?? DeepSignalTokens.of(context).fg,
      accent: accentColor ?? MojudBrand.gold,
    );
    return _Art(
      aspect: kMojudMarkAspect,
      height: height,
      painter: painter,
      label: MojudBrand.name,
    );
  }
}

/// The MOJUD wordmark, filled in a single colour.
///
/// [color] defaults to the Deep Signal foreground. Pass [height] to size by cap
/// height, or leave it null to fill the available width.
class MojudWordmark extends StatelessWidget {
  const MojudWordmark({super.key, this.height, this.color});

  /// The wordmark's cap height. When null it expands to its constraints.
  final double? height;

  /// The fill colour. Defaults to [DeepSignalTokens.fg].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _Art(
      aspect: kWordmarkAspect,
      height: height,
      painter: _WordmarkPainter(
        color: color ?? DeepSignalTokens.of(context).fg,
      ),
      label: MojudBrand.name,
    );
  }
}

/// How a [MojudLockup] arranges the monogram against the wordmark.
enum MojudLockupOrientation {
  /// Mark to the left of the wordmark — the primary lockup.
  horizontal,

  /// Mark above the wordmark — the stacked lockup, for tall/narrow space.
  stacked,
}

/// The full MOJUD lockup: monogram plus wordmark, in the brand file's
/// proportions.
///
/// [markHeight] drives the whole lockup — the wordmark and the gap between them
/// are derived from it, so the two never drift out of proportion.
class MojudLockup extends StatelessWidget {
  const MojudLockup({
    super.key,
    this.markHeight = 56,
    this.orientation = MojudLockupOrientation.horizontal,
    this.inkColor,
    this.accentColor,
  });

  /// The monogram's height. Everything else scales from it.
  final double markHeight;

  /// Horizontal (default) or stacked.
  final MojudLockupOrientation orientation;

  /// Ink for both the strokes and the wordmark. Defaults to the Deep Signal
  /// foreground.
  final Color? inkColor;

  /// The signal dot's colour. Defaults to [MojudBrand.gold].
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final ink = inkColor ?? DeepSignalTokens.of(context).fg;
    final mark = MojudMark(
      height: markHeight,
      inkColor: ink,
      accentColor: accentColor,
    );
    final wordmark = MojudWordmark(
      height: markHeight * _wordmarkScale,
      color: ink,
    );
    return Semantics(
      label: MojudBrand.name,
      image: true,
      child: ExcludeSemantics(
        child: switch (orientation) {
          MojudLockupOrientation.horizontal => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              SizedBox(width: markHeight * _horizontalGap),
              wordmark,
            ],
          ),
          MojudLockupOrientation.stacked => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              SizedBox(height: markHeight * _stackedGap),
              wordmark,
            ],
          ),
        },
      ),
    );
  }
}

/// Sizes a painter to [height] (at [aspect]) or to the incoming constraints,
/// and labels it for screen readers.
class _Art extends StatelessWidget {
  const _Art({
    required this.aspect,
    required this.painter,
    required this.label,
    this.height,
  });

  final double aspect;
  final CustomPainter painter;
  final String label;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final art = CustomPaint(painter: painter, size: Size.infinite);
    return Semantics(
      label: label,
      image: true,
      child: height == null
          ? AspectRatio(aspectRatio: aspect, child: art)
          : SizedBox(height: height, width: height! * aspect, child: art),
    );
  }
}

/// Paints the monogram, fitting the SVG geometry into whatever box it is given.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.ink, required this.accent});

  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Fit the mark's box into `size` without distorting it, then centre.
    final scale = (size.width / _markWidth) < (size.height / _markHeight)
        ? size.width / _markWidth
        : size.height / _markHeight;
    final drawn = Size(_markWidth * scale, _markHeight * scale);

    canvas.save();
    canvas.translate(
      (size.width - drawn.width) / 2,
      (size.height - drawn.height) / 2,
    );
    canvas.scale(scale);
    // The SVG's origin sits half a stroke outside the geometry; shift so the
    // round caps land inside the box rather than being clipped.
    canvas.translate(_overhang - _left, _overhang - _top);

    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Two verticals…
    canvas
      ..drawLine(
        const Offset(_left, _top),
        const Offset(_left, _bottom),
        stroke,
      )
      ..drawLine(
        const Offset(_right, _top),
        const Offset(_right, _bottom),
        stroke,
      )
      // …crossed by an upper and a lower X.
      ..drawLine(
        const Offset(_left, _top),
        const Offset(_right, _middle),
        stroke,
      )
      ..drawLine(
        const Offset(_right, _top),
        const Offset(_left, _middle),
        stroke,
      )
      ..drawLine(
        const Offset(_left, _middle),
        const Offset(_right, _bottom),
        stroke,
      )
      ..drawLine(
        const Offset(_right, _middle),
        const Offset(_left, _bottom),
        stroke,
      )
      // The signal dot at the crossing point.
      ..drawCircle(
        const Offset(_dotCentreX, _middle),
        _dotRadius,
        Paint()
          ..color = accent
          ..isAntiAlias = true,
      );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.ink != ink || old.accent != accent;
}

/// Paints the normalised wordmark outline into whatever box it is given.
class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final scale = (size.width / kWordmarkAspect) < size.height
        ? size.width / kWordmarkAspect
        : size.height;
    final drawn = Size(kWordmarkAspect * scale, scale);

    canvas.save();
    canvas.translate(
      (size.width - drawn.width) / 2,
      (size.height - drawn.height) / 2,
    );
    canvas.scale(scale);
    // The O and D counters are nested contours — even-odd knocks them out
    // regardless of the direction each contour is wound.
    canvas.drawPath(
      buildWordmarkPath()..fillType = PathFillType.evenOdd,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.color != color;
}
