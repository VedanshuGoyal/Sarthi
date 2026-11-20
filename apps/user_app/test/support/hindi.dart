// Pumps screens in Hindi on narrow phones for the layout tests in
// test/l10n/. Hindi runs longer than English, and the test font draws every
// character — vowel signs included — a full em wide, so a screen that fits
// here fits on a real phone.

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/view/widgets/vast_quiet/vast_quiet_theme.dart'
    show RideSurfaces;
import 'package:user_app/l10n/l10n.dart';

/// The phone widths every Hindi layout test runs at, in logical pixels.
const hindiWidths = [320.0, 360.0];

/// Pumps [home] in Hindi at [width] × [height] logical pixels, with the
/// app's theme and [overrides], and settles it. [L10n.current] follows, as
/// in the app; reset it in `tearDown(L10n.reset)`.
Future<void> pumpHindi(
  WidgetTester tester,
  Widget home, {
  required double width,
  double height = 2400,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: SkylineTheme.light(
          extensions: [RideSurfaces(wash: SkylineTokens.light.primarySoft)],
        ),
        locale: const Locale('hi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => L10nBinding(child: child!),
        home: home,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// No layout exception (a RenderFlex overflow, an unbounded box), and the
/// screen really is in Hindi.
void checkHindiFits(WidgetTester tester) {
  check(tester.takeException()).isNull();
  check(L10n.current.localeName).equals('hi');
  final devanagari = RegExp('[ऀ-ॿ]');
  check(
    find
        .byWidgetPredicate(
          (w) =>
              (w is Text &&
                  devanagari.hasMatch(
                    w.data ?? w.textSpan?.toPlainText() ?? '',
                  )) ||
              (w is RichText && devanagari.hasMatch(w.text.toPlainText())),
        )
        .evaluate(),
  ).isNotEmpty();
}
