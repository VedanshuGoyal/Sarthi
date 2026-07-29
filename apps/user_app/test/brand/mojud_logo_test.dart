import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/brand/mojud_brand.dart';
import 'package:user_app/core/brand/mojud_logo.dart';
import 'package:user_app/core/brand/mojud_wordmark_path.dart';
import 'package:user_app/core/theme/deep_signal/deep_signal_theme.dart';
import 'package:user_app/core/theme/deep_signal/deep_signal_tokens.dart';

/// Coverage for the painted MOJUD identity. The logo is drawn rather than
/// loaded, so these guard the two things a raster asset would give for free:
/// that it keeps its proportions at any size, and that it paints without
/// throwing under either theme mode.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DeepSignalTheme.of(brightness),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump(DeepSignalTokens.motion);
    expect(tester.takeException(), isNull);
  }

  group('MojudMark', () {
    testWidgets('sizes to the brand aspect ratio from an explicit height', (
      tester,
    ) async {
      await pump(tester, const MojudMark(height: 100));

      final size = tester.getSize(find.byType(MojudMark));
      check(size.height).equals(100);
      // 67 : 107 — the monogram's box including its round-cap overhang.
      check(size.width).isCloseTo(100 * kMojudMarkAspect, 0.01);
    });

    testWidgets('takes the brand aspect from loose constraints', (
      tester,
    ) async {
      await pump(
        tester,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
          child: const MojudMark(),
        ),
      );

      // The mark is taller than it is wide, so height is the binding edge.
      final size = tester.getSize(find.byType(MojudMark));
      check(size.height).equals(200);
      check(size.width).isCloseTo(200 * kMojudMarkAspect, 0.01);
    });

    testWidgets('letterboxes rather than distorting under tight constraints', (
      tester,
    ) async {
      // A square SizedBox forces a square; the painter must centre the mark in
      // it at the correct aspect instead of stretching to fill.
      await pump(
        tester,
        const SizedBox.square(dimension: 200, child: MojudMark()),
      );

      check(tester.getSize(find.byType(MojudMark))).equals(
        const Size.square(200),
      );
    });

    testWidgets('paints in both modes', (tester) async {
      for (final brightness in Brightness.values) {
        await pump(
          tester,
          const MojudMark(height: 64),
          brightness: brightness,
        );
      }
    });
  });

  group('MojudLockup', () {
    testWidgets('horizontal is wider than tall; stacked is the reverse', (
      tester,
    ) async {
      await pump(tester, const MojudLockup(markHeight: 60));
      final horizontal = tester.getSize(find.byType(MojudLockup));
      check(horizontal.width).isGreaterThan(horizontal.height);

      await pump(
        tester,
        const MojudLockup(
          markHeight: 60,
          orientation: MojudLockupOrientation.stacked,
        ),
      );
      final stacked = tester.getSize(find.byType(MojudLockup));
      check(stacked.height).isGreaterThan(horizontal.height);
      check(stacked.width).isLessThan(horizontal.width);
    });

    testWidgets('scales entirely from markHeight', (tester) async {
      await pump(tester, const MojudLockup(markHeight: 30));
      final small = tester.getSize(find.byType(MojudLockup));

      await pump(tester, const MojudLockup(markHeight: 60));
      final large = tester.getSize(find.byType(MojudLockup));

      // Doubling the mark must double the whole lockup, gap included.
      check(large.width).isCloseTo(small.width * 2, 0.01);
      check(large.height).isCloseTo(small.height * 2, 0.01);
    });

    testWidgets('is announced as MOJUD to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const MojudLockup(markHeight: 40));

      expect(find.bySemanticsLabel(MojudBrand.name), findsOneWidget);
      handle.dispose();
    });
  });

  group('wordmark path', () {
    test('is a closed multi-contour outline in a unit-height box', () {
      final bounds = buildWordmarkPath().getBounds();

      check(bounds.height).isCloseTo(1, 0.001);
      check(bounds.width).isCloseTo(kWordmarkAspect, 0.001);
      check(bounds.left).isCloseTo(0, 0.001);
      check(bounds.top).isCloseTo(0, 0.001);
    });

    test('knocks out the O and D counters under an even-odd fill', () {
      final path = buildWordmarkPath()..fillType = PathFillType.evenOdd;

      // The centre of the O is a hole; the stroke to its left is not.
      check(path.contains(const Offset(1.78, 0.5))).isFalse();
      check(path.contains(const Offset(1.33, 0.5))).isTrue();
    });
  });
}
