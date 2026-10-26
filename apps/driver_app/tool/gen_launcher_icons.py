"""Generate the MOJUD Driver launcher icons from the brand.

    python3 tool/gen_launcher_icons.py      (needs Pillow)

Run from `apps/driver_app/`. The geometry and renderer are the customer app's
(`apps/user_app/tool/brand_render.py`), so both icons share one monogram.

The driver tile turns the customer one around: brand-ink monogram on the gold
of the signal dot, with a cream dot. Side by side on a home screen the two
read as a pair but are never confused, and the gold matches the drivers'
section of apps.mojud.life.

Writes:

  android/app/src/main/res/
    mipmap-*/ic_launcher.png             legacy square icon
    mipmap-*/ic_launcher_foreground.png  adaptive foreground (108dp canvas)
    mipmap-*/ic_launcher_monochrome.png  themed-icon silhouette
    mipmap-anydpi-v26/ic_launcher.xml    adaptive icon definition
    values/ic_launcher_background.xml    adaptive background colour

  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png
  web/icons/Icon-{192,512}.png, Icon-maskable-{192,512}.png, web/favicon.png
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, '..', 'user_app', 'tool'))

import brand_render as br  # noqa: E402

RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
XCASSETS = os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets')
WEB = os.path.join(ROOT, 'web')

#: Android density buckets: name -> (legacy icon px, adaptive canvas px).
DENSITIES = {
    'mdpi': (48, 108),
    'hdpi': (72, 162),
    'xhdpi': (96, 216),
    'xxhdpi': (144, 324),
    'xxxhdpi': (192, 432),
}

#: Same mark size as the customer app's adaptive icon (see its generator).
ADAPTIVE_FRACTION = 0.62 * 72 / 108

BACKGROUND = br.GOLD
MARK = br.INK
DOT = br.CREAM

written = []


def save(img, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    written.append(os.path.relpath(path, ROOT))


def write_text(text, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    written.append(os.path.relpath(path, ROOT))


def tile(size, fraction=0.62):
    return br.render_icon(
        size, background=BACKGROUND, ink=MARK, gold=DOT, mark_fraction=fraction,
    )


def android_icons():
    white = (255, 255, 255, 255)
    for density, (legacy, canvas) in DENSITIES.items():
        save(tile(legacy), RES, f'mipmap-{density}', 'ic_launcher.png')
        save(
            br.render_icon(
                canvas, background=None, ink=MARK, gold=DOT,
                mark_fraction=ADAPTIVE_FRACTION,
            ),
            RES, f'mipmap-{density}', 'ic_launcher_foreground.png',
        )
        # Themed icons are tinted by the launcher: one flat colour.
        save(
            br.render_icon(
                canvas, background=None, ink=white, gold=white,
                mark_fraction=ADAPTIVE_FRACTION,
            ),
            RES, f'mipmap-{density}', 'ic_launcher_monochrome.png',
        )

    write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- The MOJUD Driver adaptive launcher icon. Regenerate with\n'
        '     `python3 tool/gen_launcher_icons.py`. -->\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n',
        RES, 'mipmap-anydpi-v26', 'ic_launcher.xml',
    )
    write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <!-- Brand gold, behind the adaptive icon foreground. -->\n'
        '    <color name="ic_launcher_background">#CE9A3C</color>\n'
        '</resources>\n',
        RES, 'values', 'ic_launcher_background.xml',
    )


def ios_icons():
    path = os.path.join(XCASSETS, 'AppIcon.appiconset')
    spec = json.load(open(os.path.join(path, 'Contents.json')))
    for entry in spec['images']:
        w, _, _ = entry['size'].partition('x')
        px = round(float(w) * float(entry['scale'].rstrip('x')))
        # iOS icons must be fully opaque — an alpha channel renders black.
        save(tile(px).convert('RGB'), path, entry['filename'])


def web_icons():
    for size in (192, 512):
        save(tile(size), WEB, 'icons', f'Icon-{size}.png')
        save(tile(size, fraction=0.44), WEB, 'icons', f'Icon-maskable-{size}.png')
    save(tile(32), WEB, 'favicon.png')


if __name__ == '__main__':
    android_icons()
    ios_icons()
    web_icons()
    print(f'wrote {len(written)} files')
