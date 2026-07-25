import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/view/trip_type_selector.dart';

Future<void> _pumpSelector(
  WidgetTester tester, {
  void Function(TripType type)? onSelected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripTypeSelector(onSelected: onSelected),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offers every trip option with no separate confirm step', (
    WidgetTester tester,
  ) async {
    await _pumpSelector(tester);

    expect(find.text('Round Trip'), findsOneWidget);
    expect(find.text('Multi-Stop Trip'), findsOneWidget);
    expect(find.text('One-Way Trip'), findsOneWidget);

    // Tap-and-go: there is no CTA button to press after picking.
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('tapping an option fires the callback immediately', (
    WidgetTester tester,
  ) async {
    TripType? selected;
    await _pumpSelector(tester, onSelected: (type) => selected = type);

    await tester.tap(find.text('Round Trip'));
    await tester.pump();

    expect(selected, TripType.roundTrip);
  });

  testWidgets('without a callback a tap surfaces the summary snackbar', (
    WidgetTester tester,
  ) async {
    await _pumpSelector(tester);

    await tester.tap(find.text('Multi-Stop Trip'));
    await tester.pump(); // let the snackbar appear

    expect(find.text('Selected: Multi-Stop Trip'), findsOneWidget);
  });

  testWidgets('the One-Way option goes straight through as well', (
    WidgetTester tester,
  ) async {
    TripType? selected;
    await _pumpSelector(tester, onSelected: (type) => selected = type);

    await tester.tap(find.text('One-Way Trip'));
    await tester.pump();

    expect(selected, TripType.oneWay);
  });
}
