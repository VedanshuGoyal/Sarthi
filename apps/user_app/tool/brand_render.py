"""Rasterise the MOJUD identity with Pillow.

Draws the same geometry `lib/core/brand/mojud_logo.dart` paints at runtime, so
the launcher icons and the native launch screens cannot drift from the in-app
logo. Everything is drawn supersampled and downsampled with Lanczos, which is
what keeps the round stroke caps clean at 48px.
"""

from PIL import Image, ImageDraw

import svg_glyphs as g

#: Draw at this multiple of the target size, then downsample.
SUPERSAMPLE = 4

INK = (26, 26, 26, 255)        # brand ink   #1A1A1A
CREAM = (242, 240, 235, 255)   # reversed lockup value
GOLD = (206, 154, 60, 255)     # signal dot  #CE9A3C


def _draw_mark(draw, box, ink, gold):
    """Draw the monogram fitted into `box` = (x, y, w, h), preserving aspect."""
    x, y, w, h = box
    scale = min(w / g.MARK_WIDTH, h / g.MARK_HEIGHT)
    ox = x + (w - g.MARK_WIDTH * scale) / 2
    oy = y + (h - g.MARK_HEIGHT * scale) / 2

    def P(px, py):
        return (
            ox + (px - g.MARK_BOX[0]) * scale,
            oy + (py - g.MARK_BOX[1]) * scale,
        )

    width = g.STROKE_WIDTH * scale
    radius = width / 2

    for (x1, y1), (x2, y2) in g.MARK_STROKES:
        a, b = P(x1, y1), P(x2, y2)
        draw.line([a, b], fill=ink, width=max(1, round(width)))
        # Pillow has no round line caps — cap each end with a disc by hand.
        for cx, cy in (a, b):
            draw.ellipse(
                [cx - radius, cy - radius, cx + radius, cy + radius], fill=ink
            )

    dx, dy = P(g.DOT_CENTRE_X, g.MIDDLE)
    dr = g.DOT_RADIUS * scale
    draw.ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=gold)


def _flatten(ops, box, aspect, steps=16):
    """Flatten the wordmark ops into polygons placed inside `box`."""
    x, y, w, h = box
    scale = min(w / aspect, h)
    ox = x + (w - aspect * scale) / 2
    oy = y + (h - scale) / 2

    def P(px, py):
        return (ox + px * scale, oy + py * scale)

    polys, cur, pos = [], [], (0.0, 0.0)
    for kind, pts in ops:
        if kind == 'move':
            if len(cur) > 2:
                polys.append(cur)
            cur, pos = [P(*pts[0])], pts[0]
        elif kind == 'line':
            cur.append(P(*pts[0]))
            pos = pts[0]
        elif kind == 'quad':
            (cx, cy), (px, py) = pts
            x0, y0 = pos
            for i in range(1, steps + 1):
                t = i / steps
                mt = 1 - t
                cur.append(
                    P(
                        mt * mt * x0 + 2 * mt * t * cx + t * t * px,
                        mt * mt * y0 + 2 * mt * t * cy + t * t * py,
                    )
                )
            pos = (px, py)
        elif kind == 'close':
            if len(cur) > 2:
                polys.append(cur)
            cur = []
    if len(cur) > 2:
        polys.append(cur)
    return polys


def _draw_wordmark(img, ops, aspect, box, colour):
    """Fill the wordmark into `img`, knocking out the O and D counters.

    The counters are nested contours, so each subpath is XOR-ed into a mask —
    an even-odd fill, which is correct regardless of contour winding.
    """
    mask = Image.new('1', img.size, 0)
    for poly in _flatten(ops, box, aspect):
        layer = Image.new('1', img.size, 0)
        ImageDraw.Draw(layer).polygon(poly, fill=1)
        mask = Image.frombytes(
            '1',
            img.size,
            bytes(a ^ b for a, b in zip(mask.tobytes(), layer.tobytes())),
        )
    img.paste(colour, (0, 0), mask)


def render_icon(size, *, background, ink, gold, mark_fraction=0.62):
    """A square app-icon tile: the monogram centred on `background`.

    `background` may be None for a transparent tile (Android adaptive
    foregrounds). `mark_fraction` is the monogram's height as a fraction of the
    tile — keep it under 0.61 for adaptive foregrounds so the mark stays inside
    the 66/108 safe zone.
    """
    n = size * SUPERSAMPLE
    img = Image.new('RGBA', (n, n), background or (0, 0, 0, 0))
    mark_h = n * mark_fraction
    _draw_mark(
        ImageDraw.Draw(img),
        (0, (n - mark_h) / 2, n, mark_h),
        ink,
        gold,
    )
    return img.resize((size, size), Image.LANCZOS)


#: The stacked lockup's gap and wordmark cap height, in monogram heights,
#: measured from `logo/mojud-logo-stacked.svg`. These must stay in step with
#: `_stackedGap` / `_wordmarkScale` in `lib/core/brand/mojud_logo.dart` so the
#: native launch screen and the Flutter splash draw the identical lockup.
STACKED_GAP = 0.231589
WORDMARK_SCALE = 0.601402


def render_lockup(svg_path, mark_height, *, ink, gold, padding=0.15):
    """The stacked lockup (monogram over wordmark) on a transparent canvas.

    Mirrors `MojudLockup(orientation: stacked)`: the gap and the wordmark's cap
    height are both derived from the monogram's height, using the same ratios
    the Dart widget uses.
    """
    ops, aspect = g.load_wordmark(svg_path)

    gap_ratio = STACKED_GAP
    word_ratio = WORDMARK_SCALE

    s = SUPERSAMPLE
    mh = mark_height * s
    mw = mh * g.MARK_ASPECT
    gap = mh * gap_ratio
    wh = mh * word_ratio
    ww = wh * aspect

    pad = mh * padding
    w = round(max(mw, ww) + 2 * pad)
    h = round(mh + gap + wh + 2 * pad)

    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(img), ((w - mw) / 2, pad, mw, mh), ink, gold)
    _draw_wordmark(img, ops, aspect, ((w - ww) / 2, pad + mh + gap, ww, wh), ink)

    return img.resize((round(w / s), round(h / s)), Image.LANCZOS)
