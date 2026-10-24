import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../deep_signal/deep_signal_tokens.dart';
import 'skyline_tokens.dart';

/// The Skyline [ThemeData] — rounded and friendly, in Deep Signal's deep navy
/// and signal blue. Both Sarthi apps use it.
///
/// Pass [light] to `MaterialApp.theme`; both apps are light only. An app adds
/// its own theme extensions (e.g. the customer app's ride surfaces) through
/// `extensions`.
/// The [ColorScheme] and component themes re-skin every Material widget
/// (buttons, fields, sheets, dialogs, pickers, snackbars) so screens built on
/// them adopt the look with no per-screen styling. Custom cards read raw
/// colours with [SkylineTokens.of].
abstract final class SkylineTheme {
  static ThemeData light({
    Iterable<ThemeExtension<dynamic>> extensions = const [],
  }) => _build(SkylineTokens.light, extensions);

  static ThemeData _build(
    SkylineTokens t,
    Iterable<ThemeExtension<dynamic>> appExtensions,
  ) {
    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: t.primary,
      onPrimary: t.onPrimary,
      primaryContainer: t.primarySoft,
      onPrimaryContainer: t.primaryText,
      secondary: t.primaryText,
      onSecondary: t.onPrimary,
      error: t.danger,
      onError: Colors.white,
      surface: t.surface,
      onSurface: t.ink,
      onSurfaceVariant: t.inkMuted,
      surfaceContainerLowest: t.surface,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.sunken,
      surfaceContainerHighest: t.sunken,
      outline: t.outline,
      outlineVariant: t.hairline,
      shadow: t.shadow,
    );

    final base = ThemeData(brightness: t.brightness).textTheme;
    final text = GoogleFonts.plusJakartaSansTextTheme(base)
        .copyWith(
          displaySmall: GoogleFonts.plusJakartaSans(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
          headlineSmall: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          titleSmall: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: t.ink, displayColor: t.ink);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Skyline.radius),
    );
    final buttonText = GoogleFonts.plusJakartaSans(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Skyline.radius),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      extensions: [
        t,
        ...appExtensions,
        // Older widgets still read Deep Signal tokens; hand them the Skyline
        // palette so nothing renders in the previous colours.
        _deepSignalCompat(t),
      ],
      scaffoldBackgroundColor: t.canvas,
      // Dropdown menus and other canvas-coloured popups read as white cards.
      canvasColor: t.surface,
      focusColor: t.primary.withValues(alpha: 0.10),
      hoverColor: t.primary.withValues(alpha: 0.05),
      textTheme: text,
      dividerColor: t.hairline,
      dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: t.canvas,
        foregroundColor: t.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: t.title(18, weight: FontWeight.w800),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.onPrimary,
          disabledBackgroundColor: t.hairline,
          disabledForegroundColor: t.inkFaint,
          minimumSize: const Size.fromHeight(Skyline.controlHeight),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.onPrimary,
          minimumSize: const Size.fromHeight(Skyline.controlHeight),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primaryText,
          backgroundColor: t.surface,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: t.outline),
          shape: buttonShape,
          textStyle: buttonText.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primaryText,
          textStyle: buttonText.copyWith(fontSize: 14),
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.surface,
        foregroundColor: t.primaryText,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: t.body(size: 15, color: t.inkFaint),
        labelStyle: t.body(size: 15),
        floatingLabelStyle: t.label(color: t.primaryText),
        prefixIconColor: t.inkMuted,
        suffixIconColor: t.inkMuted,
        border: field(t.hairline),
        enabledBorder: field(t.hairline),
        focusedBorder: field(t.signal, 2),
        errorBorder: field(t.danger),
        focusedErrorBorder: field(t.danger, 2),
        disabledBorder: field(t.hairline),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radiusLg),
          side: BorderSide(color: t.hairline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.inkMuted,
        titleTextStyle: t.title(15),
        subtitleTextStyle: t.body(size: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.surface,
        showDragHandle: true,
        dragHandleColor: t.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Skyline.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radiusLg),
        ),
        titleTextStyle: t.title(20, weight: FontWeight.w800),
        contentTextStyle: t.body(size: 15),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.isDark ? t.primarySoft : t.ink,
        contentTextStyle: t.body(
          size: 14,
          color: t.isDark ? t.ink : Colors.white,
        ),
        actionTextColor: t.isDark ? t.primaryText : const Color(0xFF9DBBFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.primarySoft,
        side: BorderSide(color: t.hairline),
        labelStyle: t.label(size: 14, color: t.ink),
        secondaryLabelStyle: t.label(size: 14, color: t.primaryText),
        checkmarkColor: t.primaryText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: t.primarySoft,
          selectedForegroundColor: t.primaryText,
          foregroundColor: t.inkMuted,
          side: BorderSide(color: t.hairline),
          textStyle: t.label(size: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Skyline.radiusSm),
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.outline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : null,
        ),
        side: BorderSide(color: t.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.hairline,
        ),
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.signal,
        linearTrackColor: t.primarySoft,
        circularTrackColor: t.primarySoft,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: t.primary,
        headerForegroundColor: t.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radiusLg),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: t.surface,
        dialBackgroundColor: t.sunken,
        hourMinuteColor: t.sunken,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radiusLg),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skyline.radius),
        ),
        textStyle: t.body(size: 15, color: t.ink),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(t.surface),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Skyline.radius),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: t.body(size: 12, color: t.canvas),
      ),
      splashColor: t.primary.withValues(alpha: 0.08),
      highlightColor: t.primary.withValues(alpha: 0.05),
    );
  }

  /// The previous design language's tokens, filled with Skyline colours.
  static DeepSignalTokens _deepSignalCompat(SkylineTokens t) =>
      DeepSignalTokens(
        brightness: t.brightness,
        canvas: t.canvas,
        surface: t.surface,
        raised: t.sunken,
        fg: t.ink,
        accent: t.signal,
        onFill: t.onPrimary,
        hairline: t.hairline,
        hairlineStrong: t.outline,
        edge: t.outline,
        soft: t.outline,
        accentBorder: t.primarySoft,
        skeleton: t.sunken,
        invertedSurface: t.primary,
        invertedFg: t.onPrimary,
        invertedAccent: t.signal,
      );
}
