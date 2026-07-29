# MOJUD brand layer

The logo is **painted, not imported**. `MojudMark` redraws the monogram's six
strokes and signal dot with `Canvas`, and `MojudWordmark` fills a normalised
outline transcoded from the brand SVG. That buys three things a PNG could not:

- it is pin-sharp at any size on any density, with no `2.0x`/`3.0x` variants;
- the ink follows the Deep Signal foreground across the light/dark toggle while
  the gold signal dot stays constant, so the logo animates with the theme;
- the whole identity costs a few hundred bytes instead of a bundled image.

## Files

| File | What it is |
| --- | --- |
| `mojud_brand.dart` | Fixed identity constants — brand gold, ink, cream, the name. |
| `mojud_logo.dart` | `MojudMark`, `MojudWordmark`, `MojudLockup`. Hand-maintained. |
| `mojud_wordmark_path.dart` | **Generated.** The wordmark outline as a `Path`. |

The originals live in the repo-root `logo/` folder and are deliberately **not**
copied into `assets/` or declared in `pubspec.yaml`: nothing in the running app
loads them, so bundling them would only add weight and a second copy to drift
out of date. The generators below read `logo/` directly.

## Regenerating the wordmark path

Only needed if `logo/mojud-logo-mono.svg` changes. From `apps/user_app/`:

```sh
python3 tool/gen_wordmark_path.py ../../logo/mojud-logo-mono.svg
```

It prints the aspect constant and the `Path` builder to stdout; paste the two
into `mojud_wordmark_path.dart` beneath its generated-file header. The script
parses only the `M/L/H/V/Q/Z` commands the brand file actually uses — if the
logo is ever redrawn with cubics or arcs, the script needs extending rather
than silently dropping segments.

## Launcher icons

App icons, adaptive icons and native launch screens are generated from the same
geometry by `tool/gen_launcher_icons.py` — see the comment at the top of that
script for what it writes where.
