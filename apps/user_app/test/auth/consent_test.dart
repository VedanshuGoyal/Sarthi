import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/core/config/legal.dart';
import 'package:user_app/features/auth/auth_providers.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';
import 'package:user_app/features/auth/view/consent_checkbox.dart';
import 'package:user_app/features/auth/view/profile_step.dart';
import 'package:user_app/features/auth/view_model/registration_view_model.dart';

/// A backend that creates every account it's asked to, recording each
/// register request's body.
http.Client _recording(List<Map<String, dynamic>> registers) =>
    MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      registers.add(body);
      return http.Response(
        jsonEncode({
          'token': 'tok-new',
          'user': {
            'id': 'u1',
            'phoneE164': body['phoneE164'],
            'name': body['name'],
            'email': body['email'],
            'dateOfBirth': body['dateOfBirth'],
          },
        }),
        201,
      );
    });

/// A flow sitting on the profile step with a valid name/email/DOB to hand.
RegistrationViewModel _onProfileStep(List<Map<String, dynamic>> registers) =>
    RegistrationViewModel(
      repository: AuthRepository(client: _recording(registers)),
      initialStep: RegistrationStep.profile,
      phoneNational: '9876543210',
    )..onDateOfBirthChanged(DateTime(2000, 1, 1));

void main() {
  group('consent at registration', () {
    test('an account is not created until the customer agrees', () async {
      final registers = <Map<String, dynamic>>[];
      final vm = _onProfileStep(registers);

      await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');

      check(vm.step).equals(RegistrationStep.profile);
      check(vm.errorText).equals(RegistrationViewModel.consentRequired);
      check(registers).isEmpty();
    });

    test('ticking the box clears the error', () async {
      final vm = _onProfileStep([]);
      await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');

      vm.onConsentChanged(true);

      check(vm.consented).isTrue();
      check(vm.errorText).isNull();
    });

    test('registering sends the consent version agreed to', () async {
      final registers = <Map<String, dynamic>>[];
      final vm = _onProfileStep(registers)..onConsentChanged(true);

      await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');

      check(vm.step).equals(RegistrationStep.done);
      check(
          registers,
        ).single.has((body) => body['consentVersion'], 'consentVersion')
        ..equals(Legal.consentVersion)
        ..equals('2026-11');
    });

    test('a register call without a version leaves the field out', () async {
      final registers = <Map<String, dynamic>>[];
      await AuthRepository(client: _recording(registers)).register(
        phoneE164: '+919876543210',
        name: 'Asha Sharma',
        email: 'asha@example.com',
        dateOfBirth: DateTime(2000, 1, 1),
      );
      check(registers.single.containsKey('consentVersion')).isFalse();
    });
  });

  group('ConsentCheckbox', () {
    testWidgets('the Terms and Privacy Policy links open the documents', (
      tester,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsentCheckbox(
              value: false,
              onChanged: (_) {},
              openLink: (url) async {
                opened.add(url);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tapOnText(find.textRange.ofSubstring('Terms'));
      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));

      check(opened).deepEquals([
        Uri.parse('https://apps.mojud.life/terms'),
        Uri.parse('https://apps.mojud.life/privacy'),
      ]);
    });

    testWidgets('the profile step asks for consent before creating it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final registers = <Map<String, dynamic>>[];
      final vm = _onProfileStep(registers);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [registrationViewModelProvider.overrideWith((ref) => vm)],
          child: const MaterialApp(home: ProfileStep()),
        ),
      );
      check(
        find.textContaining('I agree to the Terms').evaluate(),
      ).isNotEmpty();

      await tester.enterText(find.byType(TextField).at(0), 'Asha Sharma');
      await tester.enterText(find.byType(TextField).at(1), 'asha@example.com');
      await tester.tap(find.text('Create account'));
      await tester.pump();
      check(
        find.text(RegistrationViewModel.consentRequired).evaluate(),
      ).isNotEmpty();
      check(registers).isEmpty();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Create account'));
      await tester.pump();
      check(registers).single
          .has((body) => body['consentVersion'], 'consentVersion')
          .equals(Legal.consentVersion);
    });
  });
}
