import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/core/brand/mojud_logo.dart';
import 'package:user_app/features/splash/view/splash_screen.dart';

/// Coverage for the launch screen. Its signal bar animates forever, so these
/// pump fixed frames rather than settling — `pumpAndSettle` would hang.
void main() {
  Future<void> pumpSplash(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
    bool reduceMotion = false,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: DeepSignalTheme.of(brightness),
          home: const SplashScreen(),
        ),
      ),
    );
    if (settle) await tester.pump(DeepSignalTokens.motion);
  }

  testWidgets('shows the stacked MOJUD lockup on the Deep Signal canvas', (
    tester,
  ) async {
    await pumpSplash(tester);

    final lockup = tester.widget<MojudLockup>(find.byType(MojudLockup));
    check(lockup.orientation).equals(MojudLockupOrientation.stacked);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    check(scaffold.backgroundColor).equals(DeepSignalTokens.light.canvas);

    expect(tester.takeException(), isNull);
  });

  testWidgets('sizes the mark from the shortest edge, clamped on tablets', (
    tester,
  ) async {
    await pumpSplash(tester, size: const Size(390, 844));
    final phone = tester.widget<MojudLockup>(find.byType(MojudLockup));
    // 17% of the 390pt shortest edge.
    check(phone.markHeight).isCloseTo(66.3, 0.1);

    await pumpSplash(tester, size: const Size(1024, 1366));
    final tablet = tester.widget<MojudLockup>(find.byType(MojudLockup));
    // 17% of 1024 would be 174 — the clamp holds it at 104.
    check(tablet.markHeight).equals(104);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pumpSplash(tester, brightness: Brightness.dark);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    check(scaffold.backgroundColor).equals(DeepSignalTokens.dark.canvas);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lifts the lockup into place on entry', (tester) async {
    await pumpSplash(tester, settle: false);
    final start = tester.getCenter(find.byType(MojudLockup));

    await tester.pump(DeepSignalTokens.motion);
    final end = tester.getCenter(find.byType(MojudLockup));

    // It starts below its resting place and rises to it.
    check(start.dy).isGreaterThan(end.dy);
  });

  testWidgets('holds still when the OS asks for reduced motion', (
    tester,
  ) async {
    await pumpSplash(tester, reduceMotion: true, settle: false);
    final start = tester.getCenter(find.byType(MojudLockup));

    await tester.pump(DeepSignalTokens.motion);
    final end = tester.getCenter(find.byType(MojudLockup));

    // The lockup still appears — it just never travels.
    expect(find.byType(MojudLockup), findsOneWidget);
    check(start).equals(end);
    expect(tester.takeException(), isNull);
  });
}
