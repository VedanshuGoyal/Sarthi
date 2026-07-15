import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'package:user_app/features/auth/auth_providers.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';
import 'package:user_app/features/auth/view/registration_screen.dart';

import 'support/fake_backend.dart';

/// Pumps the registration flow with the backend mocked out.
Future<void> _pumpRegistration(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          AuthRepository(client: fakeBackendClient()),
        ),
      ],
      child: const MaterialApp(home: RegistrationScreen()),
    ),
  );
}

void main() {
  testWidgets('registration starts by asking for the +91 mobile number', (
    WidgetTester tester,
  ) async {
    await _pumpRegistration(tester);

    // The phone step is shown, with the fixed +91 country prefix.
    expect(find.text('Enter your mobile number'), findsWidgets);
    expect(find.text('+91'), findsOneWidget);
    expect(
      find.widgetWithText(SarthiPrimaryButton, 'Continue'),
      findsOneWidget,
    );
  });

  testWidgets('typing a valid number and continuing advances to the OTP step', (
    WidgetTester tester,
  ) async {
    await _pumpRegistration(tester);

    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Verify your number'), findsOneWidget);
  });
}
