import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the app's active [ThemeMode] — the toggle override on top of the OS
/// setting.
///
/// Defaults to [ThemeMode.system], so a fresh launch follows the device's
/// light/dark setting. Tapping the in-app control [cycle]s
/// system → light → dark → system, letting the user pin a mode regardless of
/// the OS. State is in-memory for now (it resets on relaunch); persisting it is
/// a drop-in change to this notifier.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Advance to the next mode: system → light → dark → system.
  void cycle() {
    state = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }

  /// Pin an explicit mode.
  void set(ThemeMode mode) => state = mode;
}

/// The active [ThemeMode]; drives `MaterialApp.themeMode`.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// The icon that represents [mode] in the toggle.
IconData themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

/// A short human label for [mode] ("AUTO" / "LIGHT" / "DARK").
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'AUTO',
  ThemeMode.light => 'LIGHT',
  ThemeMode.dark => 'DARK',
};

/// An app-bar-ready control that shows the current [ThemeMode] and cycles it on
/// tap. Drop it into an [AppBar.actions] list or anywhere an [IconButton] fits.
class ThemeModeToggle extends ConsumerWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return IconButton(
      onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
      icon: Icon(themeModeIcon(mode)),
      tooltip: 'Theme: ${themeModeLabel(mode)} — tap to change',
    );
  }
}
