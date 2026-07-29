"""Transcode the MOJUD wordmark into Dart `Path` calls.

    python3 tool/gen_wordmark_path.py ../../logo/mojud-logo-mono.svg

Prints the aspect constant and the `Path` builder to stdout; paste both into
`lib/core/brand/mojud_wordmark_path.dart` beneath its generated-file header.
Only needed when the brand SVG itself changes.
"""

import sys

from svg_glyphs import load_wordmark


def main(svg_path):
    ops, aspect = load_wordmark(svg_path)

    lines = []
    for kind, pts in ops:
        if kind == 'move':
            lines.append(f'    ..moveTo({pts[0][0]:.5f}, {pts[0][1]:.5f})')
        elif kind == 'line':
            lines.append(f'    ..lineTo({pts[0][0]:.5f}, {pts[0][1]:.5f})')
        elif kind == 'quad':
            (cx, cy), (x, y) = pts
            lines.append(
                f'    ..quadraticBezierTo({cx:.5f}, {cy:.5f}, {x:.5f}, {y:.5f})'
            )
        elif kind == 'close':
            lines.append('    ..close()')

    print('/// Width ÷ height of the normalised wordmark outline.')
    print(f'const double kWordmarkAspect = {aspect:.5f};')
    print()
    print('/// The "MOJUD" wordmark as a fillable path in a 1.0-height box.')
    print('Path buildWordmarkPath() => Path()')
    print('\n'.join(lines) + ';')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
