"""Parse the MOJUD wordmark outlines out of the brand SVG.

Shared by `gen_wordmark_path.py` (which emits Dart) and `brand_render.py`
(which rasterises launcher icons), so both read the identity from the same
source of truth: `logo/mojud-logo-mono.svg`.

Only the `M/L/H/V/Q/Z` commands the brand file actually uses are supported. If
the logo is ever redrawn with cubics or arcs, extend `_Walker.run` rather than
letting segments be dropped silently — `tokenize` raises on anything it does
not recognise.
"""

import re

# --- The monogram, in the source SVG's own units ----------------------------
# Two verticals crossed by four diagonals, with the signal dot at the centre.

STROKE_WIDTH = 7.0
LEFT, RIGHT = 16.0, 76.0
TOP, MIDDLE, BOTTOM = 16.0, 66.0, 116.0
DOT_CENTRE_X = 46.0
DOT_RADIUS = 5.5

#: The six strokes as ((x1, y1), (x2, y2)) pairs.
MARK_STROKES = [
    ((LEFT, TOP), (LEFT, BOTTOM)),
    ((RIGHT, TOP), (RIGHT, BOTTOM)),
    ((LEFT, TOP), (RIGHT, MIDDLE)),
    ((RIGHT, TOP), (LEFT, MIDDLE)),
    ((LEFT, MIDDLE), (RIGHT, BOTTOM)),
    ((RIGHT, MIDDLE), (LEFT, BOTTOM)),
]

#: Round caps push the drawn mark half a stroke past its geometry on each side.
_OVERHANG = STROKE_WIDTH / 2
MARK_BOX = (
    LEFT - _OVERHANG,
    TOP - _OVERHANG,
    RIGHT + _OVERHANG,
    BOTTOM + _OVERHANG,
)
MARK_WIDTH = MARK_BOX[2] - MARK_BOX[0]
MARK_HEIGHT = MARK_BOX[3] - MARK_BOX[1]
MARK_ASPECT = MARK_WIDTH / MARK_HEIGHT

_GLYPH_RE = re.compile(
    r'<path transform="translate\(([-\d.]+) ([-\d.]+)\) '
    r'scale\(([-\d.]+) ([-\d.]+)\)" d="([^"]+)"'
)
_NUM_RE = re.compile(r'-?\d*\.?\d+(?:[eE][-+]?\d+)?')


def tokenize(d):
    """Split a path `d` attribute into (command, [numbers]) pairs."""
    out = []
    i = 0
    while i < len(d):
        c = d[i]
        if c in 'MLHVQZmlhvqz':
            i += 1
            nums = []
            while i < len(d):
                m = _NUM_RE.match(d, i)
                if not m:
                    if d[i] in ' ,':
                        i += 1
                        continue
                    break
                nums.append(float(m.group()))
                i = m.end()
            out.append((c, nums))
        elif c in ' ,\n\t\r':
            i += 1
        else:
            raise ValueError(f'unsupported path command {c!r} at offset {i}')
    return out


class _Walker:
    """Replays a path, baking in the glyph's translate/scale transform."""

    def __init__(self, tx, ty, sx, sy):
        self.tx, self.ty, self.sx, self.sy = tx, ty, sx, sy
        self.ops = []
        self.pts = []
        self.cur = (0.0, 0.0)

    def _t(self, x, y):
        return (self.tx + self.sx * x, self.ty + self.sy * y)

    def _add(self, kind, *raw):
        pts = [self._t(x, y) for x, y in raw]
        self.pts.extend(pts)
        self.ops.append((kind, pts))

    def run(self, d):
        for cmd, n in tokenize(d):
            if cmd == 'M':
                for k in range(0, len(n), 2):
                    self._add('move' if k == 0 else 'line', (n[k], n[k + 1]))
                    self.cur = (n[k], n[k + 1])
            elif cmd == 'L':
                for k in range(0, len(n), 2):
                    self._add('line', (n[k], n[k + 1]))
                    self.cur = (n[k], n[k + 1])
            elif cmd == 'H':
                for x in n:
                    self._add('line', (x, self.cur[1]))
                    self.cur = (x, self.cur[1])
            elif cmd == 'V':
                for y in n:
                    self._add('line', (self.cur[0], y))
                    self.cur = (self.cur[0], y)
            elif cmd == 'Q':
                for k in range(0, len(n), 4):
                    cx, cy, x, y = n[k:k + 4]
                    self._add('quad', (cx, cy), (x, y))
                    self.cur = (x, y)
            elif cmd in 'Zz':
                self.ops.append(('close', []))
            else:
                raise ValueError(f'unsupported command {cmd!r}')
        return self


def load_wordmark(svg_path):
    """Return (ops, aspect) for the wordmark, normalised to a 1.0-high box.

    `ops` is a list of ('move'|'line'|'quad'|'close', [(x, y), ...]) with the
    outline's top-left corner at the origin.
    """
    src = open(svg_path).read()
    glyphs = [
        _Walker(float(tx), float(ty), float(sx), float(sy)).run(d)
        for tx, ty, sx, sy, d in _GLYPH_RE.findall(src)
    ]
    if not glyphs:
        raise SystemExit(f'no glyph paths found in {svg_path}')

    pts = [p for g in glyphs for p in g.pts]
    minx, maxx = min(p[0] for p in pts), max(p[0] for p in pts)
    miny, maxy = min(p[1] for p in pts), max(p[1] for p in pts)
    h = maxy - miny

    ops = []
    for g in glyphs:
        for kind, gp in g.ops:
            ops.append(
                (kind, [((x - minx) / h, (y - miny) / h) for x, y in gp])
            )
    return ops, (maxx - minx) / h
