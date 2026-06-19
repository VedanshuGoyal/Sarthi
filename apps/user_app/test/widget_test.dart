import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:user_app/main.dart';

void main() {
  testWidgets('app renders the home placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SarthiUserApp()));

    expect(find.text('Sarthi'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
  });
}
