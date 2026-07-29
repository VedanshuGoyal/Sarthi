import 'package:flutter/painting.dart';

/// The fixed MOJUD brand constants.
///
/// These are the identity's own colours, taken from `logo/mojud-icon.svg`. They
/// are deliberately *not* Deep Signal tokens: the gold signal dot is the one
/// mark element that stays constant across light and dark, so the logo reads as
/// the same logo in either mode. The monogram's ink, by contrast, is drawn in
/// the surrounding foreground colour so the mark sits in the page rather than
/// punching a black hole in it — see [MojudMark.inkColor].
abstract final class MojudBrand {
  /// The signal dot at the heart of the monogram — brand gold.
  static const Color gold = Color(0xFFCE9A3C);

  /// The identity's own ink, used where the mark must render exactly as
  /// specified in the brand files (launcher icons, native launch screens)
  /// rather than adapting to a theme.
  static const Color ink = Color(0xFF1A1A1A);

  /// The reversed lockup's light value — the cream used on [ink].
  static const Color cream = Color(0xFFF2F0EB);

  /// The wordmark as it should always be spelled.
  static const String name = 'MOJUD';
}
