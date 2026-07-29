import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'deep_signal_tokens.dart';

/// The Deep Signal [ThemeData] for a given [brightness].
///
/// Pass [light] to `MaterialApp.theme` and [dark] to `MaterialApp.darkTheme`;
/// the app picks between them from the OS setting or the in-app toggle. Both
/// register the matching [DeepSignalTokens] so cards can read raw tokens, while
/// the [ColorScheme] and component themes re-skin every Material widget
/// (buttons, inputs, dividers, app bar) into the language automatically.
///
/// Following the design, filled buttons are **ink-filled** (`primary` = the
/// foreground ink), while accent is reserved for links and status — so
/// [ColorScheme.secondary] carries the accent and text buttons are tinted with
/// it explicitly.
abstract final class DeepSignalTheme {
  /// The light theme.
  static ThemeData light() => _build(DeepSignalTokens.light);

  /// The dark theme.
  static ThemeData dark() => _build(DeepSignalTokens.dark);

  /// The theme for an explicit [brightness].
  static ThemeData of(Brightness brightness) =>
      _build(DeepSignalTokens.forBrightness(brightness));

  static ThemeData _build(DeepSignalTokens t) {
    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: t.fg,
      onPrimary: t.onFill,
      secondary: t.accent,
      onSecondary: t.onFill,
      error: t.accent,
      onError: t.onFill,
      surface: t.surface,
      onSurface: t.fg,
      onSurfaceVariant: t.fgAlpha(0.45),
      surfaceContainerHighest: t.raised,
      outline: t.edge,
      outlineVariant: t.hairline,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
    );

    final baseText = GoogleFonts.instrumentSansTextTheme(
      ThemeData(brightness: t.brightness).textTheme,
    ).apply(bodyColor: t.fg, displayColor: t.fg);

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      extensions: [t],
      scaffoldBackgroundColor: t.canvas,
      canvasColor: t.canvas,
      textTheme: baseText,
      dividerColor: t.hairline,
      dividerTheme: DividerThemeData(
        color: t.hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.canvas,
        foregroundColor: t.fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: t.title(18, weight: FontWeight.w500),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.fg,
          foregroundColor: t.onFill,
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: t.mono(size: 10.5, trackingEm: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.fg,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: t.soft),
          shape: shape,
          textStyle: t.mono(size: 10, trackingEm: 0.18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: t.accent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.fg),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: t.body(color: t.fgAlpha(0.42)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
          borderSide: BorderSide(color: t.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
          borderSide: BorderSide(color: t.hairline),
        ),
        // Focus reads as a crisp ink/near-white boundary (the foreground),
        // never a tinted accent fill — high-contrast against the field while
        // you type, in either mode.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
          borderSide: BorderSide(color: t.fg, width: 2),
        ),
      ),
      splashColor: t.accentAlpha(0.10),
      highlightColor: t.accentAlpha(0.06),
    );
  }
}
