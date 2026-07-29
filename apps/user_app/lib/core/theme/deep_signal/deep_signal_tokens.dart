import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The **Deep Signal** design language — the two-mode (light + dark) successor
/// to the single-mode Vast Quiet ride-card set.
///
/// It keeps Vast Quiet's spare rules — 2px radius (never a pill), 1px hairline
/// borders, no shadows, no gradients, 320ms motion on `cubic-bezier(.2,.8,.2,1)`,
/// a 4 / 8 / 14 / 22 / 34 spacing scale — but swaps the warm paper/terracotta
/// palette for a cool blue-ink one that resolves to a **light** and a **dark**
/// token set. Surfaces separate by *value*, never by shadow.
///
/// The tokens ride on [ThemeData] as a [ThemeExtension], so a single set of card
/// widgets renders correctly in either mode and animates across the toggle.
/// Read them with [DeepSignalTokens.of].
@immutable
class DeepSignalTokens extends ThemeExtension<DeepSignalTokens> {
  const DeepSignalTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.fg,
    required this.accent,
    required this.onFill,
    required this.hairline,
    required this.hairlineStrong,
    required this.edge,
    required this.soft,
    required this.accentBorder,
    required this.skeleton,
    required this.invertedSurface,
    required this.invertedFg,
    required this.invertedAccent,
  });

  /// Which mode these tokens describe.
  final Brightness brightness;

  /// The page behind the cards.
  final Color canvas;

  /// The standard card surface.
  final Color surface;

  /// A raised surface — a selected row, a lifted panel. In light mode this
  /// equals [surface] (selection reads from the ink border alone); in dark mode
  /// it is a distinctly lighter value.
  final Color raised;

  /// Foreground "ink" — the base text and structural colour.
  final Color fg;

  /// The single Deep Signal accent. Used sparingly: one status label, a
  /// progress dot, an alert hairline. Never a fill.
  final Color accent;

  /// Text/graphics drawn on a solid [fg] fill (e.g. the confirm button).
  final Color onFill;

  /// The hairline every card and divider is drawn with — `fg` at .10.
  final Color hairline;

  /// A slightly stronger hairline for photo/figure frames — `fg` at .14.
  final Color hairlineStrong;

  /// The unselected selection-marker border.
  final Color edge;

  /// Idle chip borders and empty stars.
  final Color soft;

  /// The accent at half strength, for an alert card's hairline border.
  final Color accentBorder;

  /// The shimmer bar fill used by loading skeletons.
  final Color skeleton;

  /// The inverted card's surface (the payment card — the one card that flips
  /// against the mode: ink in light, pale in dark).
  final Color invertedSurface;

  /// Foreground on the inverted card.
  final Color invertedFg;

  /// Accent on the inverted card (darkens against its pale dark-mode surface).
  final Color invertedAccent;

  bool get isDark => brightness == Brightness.dark;

  /// [fg] at [opacity] — for the graded label/meta text the set leans on.
  Color fgAlpha(double opacity) => fg.withValues(alpha: opacity);

  /// [accent] at [opacity].
  Color accentAlpha(double opacity) => accent.withValues(alpha: opacity);

  /// [invertedFg] at [opacity] — for muted text on the inverted card.
  Color invertedFgAlpha(double opacity) => invertedFg.withValues(alpha: opacity);

  // Graded foregrounds for secondary/tertiary text. Dark mode needs a little
  // more opacity than light to stay legible on its darker surfaces, so these
  // resolve per mode rather than being a single fixed value.

  /// Eyebrow-weight labels and row meta — the ubiquitous `.45` (light) / `.6`
  /// (dark) tint.
  Color get label => fgAlpha(isDark ? 0.6 : 0.45);

  /// Secondary text — meta lines, driver details, fare rows.
  Color get muted => fgAlpha(isDark ? 0.55 : 0.50);

  /// Tertiary text — map coordinates, faint captions.
  Color get faint => fgAlpha(isDark ? 0.50 : 0.42);

  /// The faintest text — "3 AVAILABLE", price notes, skeleton captions.
  Color get faintest => fgAlpha(isDark ? 0.45 : 0.35);

  // --- Shape & motion --------------------------------------------------------

  /// The one corner radius. 2px — sharp, never a pill.
  static const double radius = 2;

  /// Every transition in the set runs at this duration…
  static const Duration motion = Duration(milliseconds: 320);

  /// …on this easing curve — a quiet, decisive ease.
  static const Cubic easing = Cubic(0.2, 0.8, 0.2, 1);

  /// The spacing scale. Reach for these rather than arbitrary gaps.
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s14 = 14;
  static const double s22 = 22;
  static const double s34 = 34;

  // --- Type ------------------------------------------------------------------
  //
  // Font families never depend on mode — only colour does — so every builder
  // takes an explicit [color] that defaults to the mode's [fg].

  /// A display / numeral style — Instrument Sans, tight tracking. Used for
  /// fares and ETAs (e.g. the 40px arriving figure, the 44px fare).
  TextStyle display(double size, {Color? color}) => GoogleFonts.instrumentSans(
    fontSize: size,
    height: 1,
    fontWeight: FontWeight.w400,
    letterSpacing: size * -0.028,
    color: color ?? fg,
  );

  /// A title style — Instrument Sans for names and headlines.
  TextStyle title(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.2,
  }) => GoogleFonts.instrumentSans(
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: size * 0.01,
    color: color ?? fg,
  );

  /// Body copy — Instrument Sans 400, 15/22 by default.
  TextStyle body({double size = 15, Color? color, double height = 1.5}) =>
      GoogleFonts.instrumentSans(
        fontSize: size,
        height: height,
        fontWeight: FontWeight.w400,
        color: color ?? fgAlpha(0.72),
      );

  /// A mono label / figure — JetBrains Mono, with em-based tracking. The design
  /// uses uppercase eyebrow labels at `.2em` and figures at `.1–.16em`.
  TextStyle mono({
    double size = 10,
    Color? color,
    double trackingEm = 0.1,
    FontWeight weight = FontWeight.w400,
    double height = 1,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    height: height,
    fontWeight: weight,
    // The design's tracking is em-relative; Flutter's letterSpacing is in
    // logical pixels, so scale by the font size.
    letterSpacing: size * trackingEm,
    color: color ?? fgAlpha(0.45),
  );

  /// The uppercase eyebrow label ubiquitous across the set — mono, `.2em`.
  TextStyle eyebrow({Color? color, double size = 9.5}) =>
      mono(size: size, color: color ?? fgAlpha(isDark ? 0.6 : 0.45), trackingEm: 0.2);

  /// The Deep Signal tokens for [context].
  static DeepSignalTokens of(BuildContext context) =>
      Theme.of(context).extension<DeepSignalTokens>() ?? light;

  // --- The two token sets ----------------------------------------------------

  /// Light mode (design turn 1). Ink `#0B2239` on white, accent `#2A93BE`,
  /// page `#E7F0F8`.
  static const DeepSignalTokens light = DeepSignalTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFE7F0F8),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    fg: Color(0xFF0B2239),
    accent: Color(0xFF2A93BE),
    onFill: Color(0xFFF7FAFC),
    hairline: Color(0x1A0B2239), // fg .10
    hairlineStrong: Color(0x240B2239), // fg .14
    edge: Color(0x470B2239), // fg .28
    soft: Color(0x2E0B2239), // fg .18
    accentBorder: Color(0x802A93BE), // accent .50
    skeleton: Color(0xFFE0EAF3),
    invertedSurface: Color(0xFF0B2239),
    invertedFg: Color(0xFFF7FAFC),
    invertedAccent: Color(0xFF2A93BE),
  );

  /// Dark mode (design turn 2). Foreground `#DCE9F5` on `#0A1B2C`, accent
  /// `#3FBEEA`, page `#04101C`.
  static const DeepSignalTokens dark = DeepSignalTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF04101C),
    surface: Color(0xFF0A1B2C),
    raised: Color(0xFF102A42),
    fg: Color(0xFFDCE9F5),
    accent: Color(0xFF3FBEEA),
    onFill: Color(0xFF04101C),
    hairline: Color(0x1ADCE9F5), // fg .10
    hairlineStrong: Color(0x24DCE9F5), // fg .14
    edge: Color(0x5CDCE9F5), // fg .36
    soft: Color(0x3DDCE9F5), // fg .24
    accentBorder: Color(0x803FBEEA), // accent .50
    skeleton: Color(0xFF16334D),
    invertedSurface: Color(0xFFDCE9F5),
    invertedFg: Color(0xFF04101C),
    invertedAccent: Color(0xFF1B6E92),
  );

  /// Resolve the token set for a [brightness].
  static DeepSignalTokens forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  DeepSignalTokens copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? raised,
    Color? fg,
    Color? accent,
    Color? onFill,
    Color? hairline,
    Color? hairlineStrong,
    Color? edge,
    Color? soft,
    Color? accentBorder,
    Color? skeleton,
    Color? invertedSurface,
    Color? invertedFg,
    Color? invertedAccent,
  }) => DeepSignalTokens(
    brightness: brightness ?? this.brightness,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    fg: fg ?? this.fg,
    accent: accent ?? this.accent,
    onFill: onFill ?? this.onFill,
    hairline: hairline ?? this.hairline,
    hairlineStrong: hairlineStrong ?? this.hairlineStrong,
    edge: edge ?? this.edge,
    soft: soft ?? this.soft,
    accentBorder: accentBorder ?? this.accentBorder,
    skeleton: skeleton ?? this.skeleton,
    invertedSurface: invertedSurface ?? this.invertedSurface,
    invertedFg: invertedFg ?? this.invertedFg,
    invertedAccent: invertedAccent ?? this.invertedAccent,
  );

  @override
  DeepSignalTokens lerp(DeepSignalTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return DeepSignalTokens(
      // Brightness is discrete — snap at the midpoint of the transition.
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      fg: c(fg, other.fg),
      accent: c(accent, other.accent),
      onFill: c(onFill, other.onFill),
      hairline: c(hairline, other.hairline),
      hairlineStrong: c(hairlineStrong, other.hairlineStrong),
      edge: c(edge, other.edge),
      soft: c(soft, other.soft),
      accentBorder: c(accentBorder, other.accentBorder),
      skeleton: c(skeleton, other.skeleton),
      invertedSurface: c(invertedSurface, other.invertedSurface),
      invertedFg: c(invertedFg, other.invertedFg),
      invertedAccent: c(invertedAccent, other.invertedAccent),
    );
  }
}
