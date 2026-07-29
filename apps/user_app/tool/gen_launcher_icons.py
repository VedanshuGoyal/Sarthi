"""Generate every MOJUD launcher icon and native launch image from the brand.

    python3 tool/gen_launcher_icons.py

Run from `apps/user_app/`. Writes, all from the geometry in `svg_glyphs.py`:

  android/app/src/main/res/
    mipmap-*/ic_launcher.png             legacy square icon
    mipmap-*/ic_launcher_foreground.png  adaptive foreground (108dp canvas)
    mipmap-*/ic_launcher_monochrome.png  themed-icon silhouette
    mipmap-anydpi-v26/ic_launcher.xml    adaptive icon definition
    values/ic_launcher_background.xml    adaptive background colour
    drawable-*/launch_logo.png           pre-Android-12 launch lockup
    drawable-*/splash_icon.png           Android 12+ system splash icon
    values{,-night}/launch_background.xml  launch canvas, per mode

  ios/Runner/Assets.xcassets/
    AppIcon.appiconset/*.png             every size the catalog declares
    LaunchImage.imageset/*.png           light + dark launch lockups

  web/
    icons/Icon-{192,512}.png             PWA icons
    icons/Icon-maskable-{192,512}.png    maskable variants
    favicon.png

The tile is the brand's *reversed* lockup — cream monogram and gold signal dot
on brand ink. That keeps the icon opaque (a hard requirement on iOS, where an
alpha channel renders as black) and legible on any home-screen wallpaper, which
the primary ink-on-transparent mark would not be.
"""

import json
import os

from PIL import Image

import brand_render as br

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO_SVG = os.path.join(ROOT, '..', '..', 'logo', 'mojud-logo-mono.svg')
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

#: An adaptive icon's 108dp canvas is masked down to a 72dp window. Scaling the
#: legacy 0.62 fraction by 72/108 keeps the mark the same visual size, and well
#: inside the 66dp safe zone.
ADAPTIVE_FRACTION = 0.62 * 72 / 108

#: Deep Signal canvas values — the launch screen backgrounds, matched to
#: `DeepSignalTokens.canvas` so the native screen and `SplashScreen` agree.
CANVAS_LIGHT = (231, 240, 248, 255)   # #E7F0F8
CANVAS_DARK = (4, 16, 28, 255)        # #04101C
FG_LIGHT = (11, 34, 57, 255)          # #0B2239
FG_DARK = (220, 233, 245, 255)        # #DCE9F5

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
    """The standard reversed icon tile."""
    return br.render_icon(
        size, background=br.INK, ink=br.CREAM, gold=br.GOLD,
        mark_fraction=fraction,
    )


# --- Android ---------------------------------------------------------------

def android_icons():
    for density, (legacy, canvas) in DENSITIES.items():
        save(tile(legacy), RES, f'mipmap-{density}', 'ic_launcher.png')

        save(
            br.render_icon(
                canvas, background=None, ink=br.CREAM, gold=br.GOLD,
                mark_fraction=ADAPTIVE_FRACTION,
            ),
            RES, f'mipmap-{density}', 'ic_launcher_foreground.png',
        )

        # Themed icons are tinted by the launcher, so the dot cannot stay gold —
        # the silhouette is drawn in one flat colour.
        white = (255, 255, 255, 255)
        save(
            br.render_icon(
                canvas, background=None, ink=white, gold=white,
                mark_fraction=ADAPTIVE_FRACTION,
            ),
            RES, f'mipmap-{density}', 'ic_launcher_monochrome.png',
        )

    write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- The MOJUD adaptive launcher icon. Regenerate with\n'
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
        '    <!-- Brand ink, behind the adaptive icon foreground. -->\n'
        '    <color name="ic_launcher_background">#1A1A1A</color>\n'
        '</resources>\n',
        RES, 'values', 'ic_launcher_background.xml',
    )

    # The launch background tracks DeepSignalTokens.canvas in each mode, so the
    # native screen and SplashScreen sit on the same colour.
    for folder, comment, value in (
        ('values', 'Deep Signal light canvas', '#E7F0F8'),
        ('values-night', 'Deep Signal dark canvas', '#04101C'),
    ):
        write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            f'    <!-- {comment} — matches DeepSignalTokens.canvas. -->\n'
            f'    <color name="launch_background">{value}</color>\n'
            '</resources>\n',
            RES, folder, 'launch_background.xml',
        )


#: Density multipliers, relative to mdpi.
SCALES = (('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3),
          ('xxxhdpi', 4))

#: Monogram height, in dp/pt, for the native launch lockup. `SplashScreen`
#: sizes its mark at 17% of the shortest screen edge, which lands near 64 on a
#: typical phone (54 on an SE, 67 on a 6.1"), so a fixed 64 here keeps the
#: native-to-Flutter handover from visibly resizing the logo.
LAUNCH_MARK_DP = 64

#: Android 12+ draws the system splash icon on a 288dp canvas, of which only a
#: centred 192dp circle is guaranteed visible. Matching the 0.62 mark fraction
#: inside that circle gives 192/288 * 0.62.
SPLASH_ICON_DP = 288
SPLASH_ICON_FRACTION = 0.62 * 192 / 288


def android_launch_logos():
    """Launch-screen art for the native splash, per density and mode.

    `launch_logo` is the stacked lockup used by the pre-Android-12 window
    background; `splash_icon` is the monogram alone, for the Android 12+ system
    splash, which only ever shows a centred icon.
    """
    for density, scale in SCALES:
        for suffix, ink in (('', FG_LIGHT), ('-night', FG_DARK)):
            save(
                br.render_lockup(
                    LOGO_SVG, round(LAUNCH_MARK_DP * scale),
                    ink=ink, gold=br.GOLD,
                ),
                RES, f'drawable{suffix}-{density}', 'launch_logo.png',
            )
            save(
                br.render_icon(
                    round(SPLASH_ICON_DP * scale), background=None,
                    ink=ink, gold=br.GOLD,
                    mark_fraction=SPLASH_ICON_FRACTION,
                ),
                RES, f'drawable{suffix}-{density}', 'splash_icon.png',
            )


# --- iOS -------------------------------------------------------------------

def ios_icons():
    path = os.path.join(XCASSETS, 'AppIcon.appiconset')
    spec = json.load(open(os.path.join(path, 'Contents.json')))

    for entry in spec['images']:
        w, _, h = entry['size'].partition('x')
        px = round(float(w) * float(entry['scale'].rstrip('x')))
        # iOS icons must be fully opaque — an alpha channel is rendered black.
        save(
            tile(px).convert('RGB'),
            path, entry['filename'],
        )


def ios_launch_images():
    path = os.path.join(XCASSETS, 'LaunchImage.imageset')
    images = []
    for scale in (1, 2, 3):
        for name, ink, appearance in (
            ('LaunchImage', FG_LIGHT, None),
            ('LaunchImage-dark', FG_DARK, 'dark'),
        ):
            filename = f'{name}{"" if scale == 1 else f"@{scale}x"}.png'
            save(
                br.render_lockup(
                    LOGO_SVG, LAUNCH_MARK_DP * scale, ink=ink, gold=br.GOLD,
                ),
                path, filename,
            )
            entry = {
                'idiom': 'universal',
                'filename': filename,
                'scale': f'{scale}x',
            }
            if appearance:
                entry['appearances'] = [
                    {'appearance': 'luminosity', 'value': appearance}
                ]
            images.append(entry)

    write_text(
        json.dumps(
            {'images': images, 'info': {'version': 1, 'author': 'xcode'}},
            indent=2,
        ) + '\n',
        path, 'Contents.json',
    )

    # A launch background that follows the system appearance, referenced by
    # LaunchScreen.storyboard.
    colorset = os.path.join(XCASSETS, 'LaunchBackground.colorset')

    def components(rgba):
        r, g_, b, _ = rgba
        return {
            'alpha': '1.000',
            'blue': f'0x{b:02X}',
            'green': f'0x{g_:02X}',
            'red': f'0x{r:02X}',
        }

    write_text(
        json.dumps(
            {
                'colors': [
                    {
                        'idiom': 'universal',
                        'color': {
                            'color-space': 'srgb',
                            'components': components(CANVAS_LIGHT),
                        },
                    },
                    {
                        'idiom': 'universal',
                        'appearances': [
                            {'appearance': 'luminosity', 'value': 'dark'}
                        ],
                        'color': {
                            'color-space': 'srgb',
                            'components': components(CANVAS_DARK),
                        },
                    },
                ],
                'info': {'version': 1, 'author': 'xcode'},
            },
            indent=2,
        ) + '\n',
        colorset, 'Contents.json',
    )


# --- Web -------------------------------------------------------------------

def web_icons():
    for size in (192, 512):
        save(tile(size), WEB, 'icons', f'Icon-{size}.png')
        # Maskable icons are cropped to a centred circle of ~80% — pull the
        # mark in so nothing important is clipped.
        save(
            tile(size, fraction=0.44),
            WEB, 'icons', f'Icon-maskable-{size}.png',
        )
    save(tile(32), WEB, 'favicon.png')


if __name__ == '__main__':
    android_icons()
    android_launch_logos()
    ios_icons()
    ios_launch_images()
    web_icons()
    print(f'wrote {len(written)} files:')
    for p in sorted(written):
        print(f'  {p}')
