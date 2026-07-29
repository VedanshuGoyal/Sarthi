import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/theme/deep_signal/deep_signal.dart';
import 'package:user_app/core/theme/deep_signal/deep_signal_gallery.dart';
import 'package:user_app/core/theme/theme_mode_controller.dart';

/// Pumps the full card gallery under the Deep Signal theme in [mode]. The
/// gallery renders every one of the ten cards, so a clean pump exercises the
/// whole set — including the animated skeleton and the fare-expand — in that
/// mode.
Future<void> pumpGallery(WidgetTester tester, ThemeMode mode) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [],
      child: MaterialApp(
        theme: DeepSignalTheme.light(),
        darkTheme: DeepSignalTheme.dark(),
        themeMode: mode,
        home: const DeepSignalGalleryScreen(),
      ),
    ),
  );
  // The skeleton animates forever, so settle a fixed number of frames rather
  // than pumpAndSettle (which would time out).
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('DeepSignalTokens', () {
    test('light and dark carry their own brightness', () {
      expect(DeepSignalTokens.light.brightness, Brightness.light);
      expect(DeepSignalTokens.dark.brightness, Brightness.dark);
      expect(DeepSignalTokens.dark.isDark, isTrue);
    });

    test('forBrightness resolves the matching set', () {
      expect(DeepSignalTokens.forBrightness(Brightness.dark), DeepSignalTokens.dark);
      expect(DeepSignalTokens.forBrightness(Brightness.light), DeepSignalTokens.light);
    });

    test('alpha helpers grade the foreground', () {
      final faded = DeepSignalTokens.light.fgAlpha(0.5);
      expect(faded.a, closeTo(0.5, 0.01));
    });

    test('lerp snaps brightness at the midpoint', () {
      final a = DeepSignalTokens.light.lerp(DeepSignalTokens.dark, 0.25);
      final b = DeepSignalTokens.light.lerp(DeepSignalTokens.dark, 0.75);
      expect(a.brightness, Brightness.light);
      expect(b.brightness, Brightness.dark);
    });
  });

  // Building the theme instantiates google_fonts text styles, whose offline
  // font-load is tolerated under testWidgets but throws in a plain test().
  group('DeepSignalTheme', () {
    testWidgets('registers the matching tokens extension', (tester) async {
      expect(
        DeepSignalTheme.light().extension<DeepSignalTokens>(),
        DeepSignalTokens.light,
      );
      expect(
        DeepSignalTheme.dark().extension<DeepSignalTokens>(),
        DeepSignalTokens.dark,
      );
    });

    testWidgets('maps ink to primary and accent to secondary', (tester) async {
      final light = DeepSignalTheme.light().colorScheme;
      expect(light.primary, DeepSignalTokens.light.fg);
      expect(light.secondary, DeepSignalTokens.light.accent);
    });
  });

  group('ThemeModeController', () {
    test('defaults to system and cycles system → light → dark → system', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(themeModeProvider.notifier);

      expect(container.read(themeModeProvider), ThemeMode.system);
      controller.cycle();
      expect(container.read(themeModeProvider), ThemeMode.light);
      controller.cycle();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      controller.cycle();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });

  group('Card gallery', () {
    testWidgets('renders every card in light mode', (tester) async {
      await pumpGallery(tester, ThemeMode.light);
      expect(tester.takeException(), isNull);
      // Content from several different cards proves they all built.
      expect(find.text('Glide Quiet'), findsWidgets);
      expect(find.text('£18.40'), findsWidgets);
      expect(find.text('Marcus Oyelaran'), findsOneWidget);
    });

    testWidgets('renders every card in dark mode', (tester) async {
      await pumpGallery(tester, ThemeMode.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('Glide Quiet'), findsWidgets);
      expect(find.text('Marcus Oyelaran'), findsOneWidget);
    });

    testWidgets('ride selection responds to taps', (tester) async {
      await pumpGallery(tester, ThemeMode.light);
      // Confirm button label reflects the selected ride.
      expect(find.text('CONFIRM GLIDE QUIET'), findsOneWidget);
      await tester.tap(find.text('Ledger XL'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('CONFIRM LEDGER XL'), findsOneWidget);
    });
  });
}
