import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'mojud_brand.dart';
import 'mojud_logo.dart';

/// Registers both Deep Signal modes so the brand previews render either.
PreviewThemeData brandPreviewTheme() => PreviewThemeData(
  materialLight: DeepSignalTheme.light(),
  materialDark: DeepSignalTheme.dark(),
);

/// Frames [child] on a mode's canvas, as the logo sits in the app.
Widget _stage(DeepSignalTokens tokens, Widget child) => Theme(
  data: DeepSignalTheme.of(tokens.brightness),
  child: ColoredBox(
    color: tokens.canvas,
    child: Padding(
      padding: const EdgeInsets.all(DeepSignalTokens.s34),
      child: Center(child: child),
    ),
  ),
);

/// Light and dark side by side — the point of painting the logo is that one
/// widget serves both, so every brand preview shows the pair.
Widget _dual(Widget Function() build) => Row(
  children: [
    Expanded(child: _stage(DeepSignalTokens.light, build())),
    Expanded(child: _stage(DeepSignalTokens.dark, build())),
  ],
);

@Preview(name: 'Lockup — horizontal', group: 'Brand', theme: brandPreviewTheme)
Widget lockupHorizontalPreview() =>
    _dual(() => const MojudLockup(markHeight: 64));

@Preview(name: 'Lockup — stacked', group: 'Brand', theme: brandPreviewTheme)
Widget lockupStackedPreview() => _dual(
  () => const MojudLockup(
    markHeight: 64,
    orientation: MojudLockupOrientation.stacked,
  ),
);

/// The mark has to stay legible from an app-bar glyph up to a splash logo.
@Preview(name: 'Mark — size ramp', group: 'Brand', theme: brandPreviewTheme)
Widget markSizeRampPreview() => _dual(
  () => const Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      MojudMark(height: 16),
      SizedBox(width: DeepSignalTokens.s14),
      MojudMark(height: 24),
      SizedBox(width: DeepSignalTokens.s14),
      MojudMark(height: 40),
      SizedBox(width: DeepSignalTokens.s14),
      MojudMark(height: 72),
    ],
  ),
);

/// The reversed lockup, as it appears on the launcher icon tile — fixed brand
/// colours rather than theme-derived ones, so it reads the same in both modes.
@Preview(name: 'Reversed (icon tile)', group: 'Brand', theme: brandPreviewTheme)
Widget reversedPreview() => _dual(
  () => ColoredBox(
    color: MojudBrand.ink,
    child: const Padding(
      padding: EdgeInsets.all(DeepSignalTokens.s22),
      child: MojudLockup(
        markHeight: 56,
        orientation: MojudLockupOrientation.stacked,
        inkColor: MojudBrand.cream,
      ),
    ),
  ),
);

/// The wordmark alone, at the width it is typically set.
@Preview(name: 'Wordmark', group: 'Brand', theme: brandPreviewTheme)
Widget wordmarkPreview() => _dual(() => const MojudWordmark(height: 30));
