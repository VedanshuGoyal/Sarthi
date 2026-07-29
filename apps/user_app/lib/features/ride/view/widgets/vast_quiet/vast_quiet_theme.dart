import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// The **Vast Quiet** design language for the rider card set.
///
/// A warm, quiet, editorial system: paper-and-ink neutrals lifted by a single
/// terracotta accent ("alpenglow"), typeset in Instrument Sans with JetBrains
/// Mono for labels and figures. The rules are deliberately spare —
///
/// * radius **2px**, never a pill;
/// * borders are **1px hairlines** at `rgba(17,17,17,.10)`;
/// * **no shadows, no gradients** (the only "texture" is a hatch placeholder);
/// * motion is **320ms** on `cubic-bezier(.2,.8,.2,1)`;
/// * spacing steps on the **4 / 8 / 14 / 22 / 34** scale.
///
/// [VastQuiet] holds the raw tokens (colours, type, timing). [vastQuietTheme]
/// assembles them into a [ThemeData] the ride flow wraps itself in, so Material
/// widgets inside adopt the aesthetic without every screen re-declaring it.
abstract final class VastQuiet {
  // --- Palette -------------------------------------------------------------

  /// Near-black text and structural fills.
  static const Color ink = Color(0xFF111111);

  /// The page behind the cards.
  static const Color paper = Color(0xFFF4F3F1);

  /// The single accent — a terracotta "alpenglow". Used sparingly: one status
  /// label, a progress dot, an alert hairline. Never a fill.
  static const Color alpenglow = Color(0xFFC4796A);

  /// The card surface.
  static const Color surface = Color(0xFFFFFFFF);

  // Ink at the opacities the design leans on, precomputed as const ARGB so the
  // tokens stay `const` (Color.withValues is not a const expression).
  static const Color ink72 = Color(0xB8111111); // body on surface
  static const Color ink60 = Color(0x99111111); // secondary body
  static const Color ink50 = Color(0x80111111); // muted meta
  static const Color ink45 = Color(0x73111111); // label
  static const Color ink42 = Color(0x6B111111); // faint meta
  static const Color ink35 = Color(0x59111111); // faintest text
  static const Color ink28 = Color(0x47111111); // unselected marker border
  static const Color ink18 = Color(0x2E111111); // idle chip border / empty star

  /// The hairline every card and divider is drawn with — `rgba(17,17,17,.10)`.
  static const Color hairline = Color(0x1A111111);

  /// A slightly stronger hairline for photo/figure frames — `…,.14`.
  static const Color hairlineStrong = Color(0x24111111);

  /// The alpenglow at half strength, for the surge card's alert border.
  static const Color alpenglowHairline = Color(0x80C4796A);

  // On the one inverted (ink) card, text is white at these opacities.
  static const Color onInk = Color(0xFFFFFFFF);
  static const Color onInk55 = Color(0x8CFFFFFF);
  static const Color onInk50 = Color(0x80FFFFFF);

  // --- Shape & motion ------------------------------------------------------

  /// The one corner radius. 2px — sharp, never a pill.
  static const double radius = 2;

  /// The hairline border used on cards and dividers.
  static const BorderSide hairlineSide = BorderSide(color: hairline);

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

  // --- Type ----------------------------------------------------------------

  /// A display / numeral style — Instrument Sans, tight tracking. Used for
  /// fares and ETAs (e.g. `40px` arriving figure, `44px` fare).
  static TextStyle display(double size, {Color color = ink}) =>
      GoogleFonts.instrumentSans(
        fontSize: size,
        height: 1,
        fontWeight: FontWeight.w400,
        letterSpacing: size * -0.028,
        color: color,
      );

  /// A title style — Instrument Sans 400/500 for names and headlines.
  static TextStyle title(
    double size, {
    Color color = ink,
    FontWeight weight = FontWeight.w400,
    double height = 1.2,
  }) => GoogleFonts.instrumentSans(
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: size * 0.01,
    color: color,
  );

  /// Body copy — Instrument Sans 400, 15/22 by default.
  static TextStyle body({
    double size = 15,
    Color color = ink72,
    double height = 1.5,
  }) => GoogleFonts.instrumentSans(
    fontSize: size,
    height: height,
    fontWeight: FontWeight.w400,
    color: color,
  );

  /// A mono label / figure — JetBrains Mono, with em-based tracking. The design
  /// uses uppercase eyebrow labels at `.2em` tracking and figures at `.1–.16em`.
  static TextStyle mono({
    double size = 10,
    Color color = ink45,
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
    color: color,
  );

  /// The uppercase eyebrow label ubiquitous across the set — mono, `.2em`.
  static TextStyle eyebrow({Color color = ink45, double size = 9.5}) =>
      mono(size: size, color: color, trackingEm: 0.2);
}

/// Carries the ride flow's info-panel "wash" — the subtle fill behind
/// read-only panels like the route echo and the drive-time estimate.
///
/// Screens read it through [washOf], which falls back to the ultramarine
/// theme's [SarthiColors.ultramarineWash] when no [RideSurfaces] is installed.
/// [vastQuietTheme] registers a neutral paper wash instead, so the same shared
/// widgets re-skin themselves the moment a screen is wrapped in Vast Quiet —
/// without hardcoding either palette into the widget.
@immutable
class RideSurfaces extends ThemeExtension<RideSurfaces> {
  const RideSurfaces({required this.wash});

  /// The fill behind read-only info panels.
  final Color wash;

  /// The active wash for [context] — the installed [RideSurfaces], or the
  /// ultramarine default when none is present.
  static Color washOf(BuildContext context) =>
      Theme.of(context).extension<RideSurfaces>()?.wash ??
      SarthiColors.ultramarineWash;

  @override
  RideSurfaces copyWith({Color? wash}) =>
      RideSurfaces(wash: wash ?? this.wash);

  @override
  RideSurfaces lerp(RideSurfaces? other, double t) => RideSurfaces(
    wash: Color.lerp(wash, other?.wash, t) ?? wash,
  );
}

/// The ride-flow [ThemeData]. Wrap the ride screens in `Theme(data:
/// vastQuietTheme(), …)` (or pass it to a nested navigator) so Material
/// components — buttons, inputs, dividers, app bar — inherit Vast Quiet's
/// palette, 2px radius, and Instrument Sans type.
ThemeData vastQuietTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: VastQuiet.ink,
    onPrimary: VastQuiet.onInk,
    secondary: VastQuiet.alpenglow,
    onSecondary: VastQuiet.onInk,
    error: VastQuiet.alpenglow,
    onError: VastQuiet.onInk,
    surface: VastQuiet.surface,
    onSurface: VastQuiet.ink,
    onSurfaceVariant: VastQuiet.ink45,
    outline: VastQuiet.ink28,
    outlineVariant: VastQuiet.hairline,
  );

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(VastQuiet.radius),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: const [RideSurfaces(wash: Color(0xFFEDEBE8))],
    scaffoldBackgroundColor: VastQuiet.paper,
    textTheme: GoogleFonts.instrumentSansTextTheme().apply(
      bodyColor: VastQuiet.ink,
      displayColor: VastQuiet.ink,
    ),
    dividerColor: VastQuiet.hairline,
    appBarTheme: AppBarTheme(
      backgroundColor: VastQuiet.paper,
      foregroundColor: VastQuiet.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: VastQuiet.title(18, weight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VastQuiet.ink,
        foregroundColor: VastQuiet.onInk,
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        textStyle: VastQuiet.mono(size: 10.5, trackingEm: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VastQuiet.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: VastQuiet.ink18),
        shape: shape,
        textStyle: VastQuiet.mono(size: 10, trackingEm: 0.18),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: VastQuiet.alpenglow),
    ),
  );
}
