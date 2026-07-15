import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/view/trip_type_selector.dart';

Future<void> _pumpSelector(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TripTypeSelector()),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offers both trip options with the CTA disabled until a pick', (
    WidgetTester tester,
  ) async {
    await _pumpSelector(tester);

    expect(find.text('Round Trip'), findsOneWidget);
    expect(find.text('Multi-Stop Trip'), findsOneWidget);

    // No selection yet → Continue is disabled.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('picking an option enables the CTA', (
    WidgetTester tester,
  ) async {
    await _pumpSelector(tester);

    await tester.tap(find.text('Round Trip'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('confirming a selection surfaces a summary snackbar', (
    WidgetTester tester,
  ) async {
    await _pumpSelector(tester);

    await tester.tap(find.text('Multi-Stop Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Continue'));
    await tester.pump(); // let the snackbar appear

    expect(find.text('Selected: Multi-Stop Trip'), findsOneWidget);
  });
}
