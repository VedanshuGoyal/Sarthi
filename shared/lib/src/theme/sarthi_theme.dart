import 'package:flutter/material.dart';

import 'sarthi_colors.dart';

/// Builds the shared Material 3 theme for every Sarthi app.
///
/// The colour scheme is seeded from [SarthiColors.ultramarine] so the whole
/// app derives harmonious tones from the brand colour, while [primary] is
/// pinned to the exact ultramarine so buttons and accents match the brand
/// guideline precisely. Both apps call [SarthiTheme.light] (and later
/// [SarthiTheme.dark]) instead of declaring their own [ThemeData], keeping the
/// design scheme common across the customer and driver apps.
abstract final class SarthiTheme {
  /// Corner radius used consistently across inputs, buttons, and cards.
  static const double radius = 12;

  /// The light theme. Pass the result straight to `MaterialApp.theme`.
  static ThemeData light() => _build(Brightness.light);

  /// The dark theme. Pass the result to `MaterialApp.darkTheme`.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: SarthiColors.ultramarine,
      brightness: brightness,
      // Pin the brand colour exactly rather than letting the tonal palette
      // shift it.
      primary: isLight
          ? SarthiColors.ultramarine
          : SarthiColors.ultramarineLight,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight ? Colors.white : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // A faint tint so fields stay visible against the white page.
        fillColor: isLight
            ? SarthiColors.surface
            : scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}
