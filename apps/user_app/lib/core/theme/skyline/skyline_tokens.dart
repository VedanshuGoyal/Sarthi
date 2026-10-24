import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shape, spacing and motion constants of the **Skyline** design language —
/// the customer app's rounded, friendly look, in Deep Signal's blues.
///
/// Mode-independent, so they are plain constants; colours live on
/// [SkylineTokens], which changes with light/dark.
abstract final class Skyline {
  /// Chips, small tiles, icon wells.
  static const double radiusSm = 12;

  /// Inputs, buttons, list rows — the everyday radius.
  static const double radius = 18;

  /// Cards and panels.
  static const double radiusLg = 24;

  /// Bottom sheets and hero cards.
  static const double radiusXl = 32;

  /// Every transition runs at this duration…
  static const Duration motion = Duration(milliseconds: 260);

  /// …on this easing curve.
  static const Curve easing = Curves.easeOutCubic;

  /// The spacing scale.
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  /// Standard height of primary actions and text fields.
  static const double controlHeight = 56;
}

/// The Skyline colour tokens, carried on [ThemeData] as a [ThemeExtension] so
/// custom cards read them with [SkylineTokens.of]. The app ships the [light]
/// set only.
@immutable
class SkylineTokens extends ThemeExtension<SkylineTokens> {
  const SkylineTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.sunken,
    required this.primary,
    required this.primaryText,
    required this.primarySoft,
    required this.onPrimary,
    required this.signal,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.hairline,
    required this.outline,
    required this.success,
    required this.danger,
    required this.shadow,
  });

  final Brightness brightness;

  /// The page behind everything.
  final Color canvas;

  /// Cards, sheets, fields.
  final Color surface;

  /// A panel set into a surface (an address row inside a sheet).
  final Color sunken;

  /// The fill of primary actions and the featured card — Deep Signal's deep
  /// navy in light mode, its signal blue in dark mode.
  final Color primary;

  /// Blue for text and icons drawn on [surface] (lighter in dark mode so it
  /// keeps its contrast).
  final Color primaryText;

  /// A pale blue wash — icon wells, selected rows, the location halo.
  final Color primarySoft;

  /// Text and icons on a [primary] fill.
  final Color onPrimary;

  /// The Deep Signal blue — icon wells, the pin's dot, focus rings, progress.
  /// Decorative: text in this hue uses [primaryText], which keeps contrast.
  final Color signal;

  /// Body text and headings.
  final Color ink;

  /// Secondary text — subtitles, meta lines.
  final Color inkMuted;

  /// Tertiary text — hints, captions.
  final Color inkFaint;

  /// Dividers and quiet borders.
  final Color hairline;

  /// Stronger borders — an outlined button, an unselected radio.
  final Color outline;

  /// Confirmations.
  final Color success;

  /// Errors.
  final Color danger;

  /// Base colour of the soft drop shadows.
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// The resting shadow under a card.
  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadow.withValues(alpha: isDark ? 0.30 : 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// The lifted shadow under floating controls and sheets.
  List<BoxShadow> get floatShadow => [
    BoxShadow(
      color: shadow.withValues(alpha: isDark ? 0.45 : 0.12),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// The coloured glow under the primary call to action.
  List<BoxShadow> get primaryGlow => [
    BoxShadow(
      color: primary.withValues(alpha: isDark ? 0.35 : 0.28),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  // --- Type ------------------------------------------------------------------

  /// Big headings — Plus Jakarta Sans ExtraBold.
  TextStyle heading(double size, {Color? color}) => GoogleFonts.plusJakartaSans(
    fontSize: size,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: size * -0.01,
    color: color ?? ink,
  );

  /// Titles of cards and rows.
  TextStyle title(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w700,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: size,
    height: 1.3,
    fontWeight: weight,
    color: color ?? ink,
  );

  /// Body copy.
  TextStyle body({double size = 14, Color? color, double height = 1.45}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        height: height,
        fontWeight: FontWeight.w500,
        color: color ?? inkMuted,
      );

  /// Small bold labels above fields and sections.
  TextStyle label({double size = 13, Color? color}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: color ?? inkMuted,
      );

  /// Figures — fares, times, counts — with tabular numerals so they don't jog.
  TextStyle figure(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        height: 1.1,
        fontWeight: weight ?? FontWeight.w800,
        color: color ?? ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// The Skyline tokens for [context].
  static SkylineTokens of(BuildContext context) =>
      Theme.of(context).extension<SkylineTokens>() ?? light;

  // --- The two token sets ----------------------------------------------------

  // Colours follow the app's Deep Signal palette (deep navy + signal blue)
  // in Skyline's softer, rounded form.
  static const light = SkylineTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFE7F0F8),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEEF4FA),
    primary: Color(0xFF0B2239),
    primaryText: Color(0xFF1A6E93),
    primarySoft: Color(0xFFD6EAF4),
    onPrimary: Color(0xFFFFFFFF),
    signal: Color(0xFF2A93BE),
    ink: Color(0xFF0B2239),
    inkMuted: Color(0xFF4A5D72),
    inkFaint: Color(0xFF56697E),
    hairline: Color(0xFFDCE7F1),
    outline: Color(0xFFBFD0E0),
    success: Color(0xFF047857),
    danger: Color(0xFFC81E1E),
    shadow: Color(0xFF0B2239),
  );

  @override
  SkylineTokens copyWith() => this;

  @override
  SkylineTokens lerp(ThemeExtension<SkylineTokens>? other, double t) {
    if (other is! SkylineTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SkylineTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      sunken: c(sunken, other.sunken),
      primary: c(primary, other.primary),
      primaryText: c(primaryText, other.primaryText),
      primarySoft: c(primarySoft, other.primarySoft),
      onPrimary: c(onPrimary, other.onPrimary),
      signal: c(signal, other.signal),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      hairline: c(hairline, other.hairline),
      outline: c(outline, other.outline),
      success: c(success, other.success),
      danger: c(danger, other.danger),
      shadow: c(shadow, other.shadow),
    );
  }
}
