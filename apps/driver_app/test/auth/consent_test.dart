import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/core/config/legal.dart';
import 'package:driver_app/features/auth/data/driver_auth_repository.dart';
import 'package:driver_app/features/auth/driver_auth_providers.dart';
import 'package:driver_app/features/auth/view/consent_checkbox.dart';
import 'package:driver_app/features/auth/view/name_step.dart';
import 'package:driver_app/features/auth/view_model/driver_registration_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// A backend that records every register body and signs the driver in.
http.Client _backend(List<Map<String, dynamic>> registrations) =>
    MockClient((request) async {
      if (request.url.path == '/driver/auth/register') {
        registrations.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'registered': true,
            'token': 'tok-new',
            'driver': {
              'id': 'd9',
              'phoneE164': '+919876543210',
              'name': 'Ravi Kumar',
            },
          }),
          201,
        );
      }
      return http.Response('not found', 404);
    });

DriverRegistrationViewModel _atNameStep(http.Client client) =>
    DriverRegistrationViewModel(
      repository: DriverAuthRepository(client: client),
      initialStep: DriverRegistrationStep.name,
      phoneNational: '9876543210',
    );

void main() {
  group('consent at registration', () {
    test(
      'registering without agreeing is refused before any request',
      () async {
        final registrations = <Map<String, dynamic>>[];
        final vm = _atNameStep(_backend(registrations));

        await vm.submitName('Ravi Kumar');

        check(registrations).isEmpty();
        check(vm.errorText).equals(DriverRegistrationViewModel.consentRequired);
        check(vm.step).equals(DriverRegistrationStep.name);
        vm.dispose();
      },
    );

    test('agreeing sends the consent version with the registration', () async {
      final registrations = <Map<String, dynamic>>[];
      final vm = _atNameStep(_backend(registrations));

      vm.setConsent(true);
      await vm.submitName('Ravi Kumar');

      check(registrations).length.equals(1);
      check(registrations.single)
        ..['consentVersion'].equals(Legal.consentVersion)
        ..['name'].equals('Ravi Kumar');
      check(Legal.consentVersion).equals('2026-11');
      check(vm.step).equals(DriverRegistrationStep.done);
      vm.dispose();
    });

    test('ticking the box clears the "agree first" error', () async {
      final vm = _atNameStep(_backend([]));
      await vm.submitName('Ravi Kumar');
      check(vm.errorText).isNotNull();

      vm.setConsent(true);

      check(vm.hasConsented).isTrue();
      check(vm.errorText).isNull();
      vm.dispose();
    });

    test('the repository leaves consentVersion out when not given', () async {
      final registrations = <Map<String, dynamic>>[];
      await DriverAuthRepository(
        client: _backend(registrations),
      ).register(phoneE164: '+919876543210', name: 'Ravi');

      check(registrations.single.containsKey('consentVersion')).isFalse();
    });

    testWidgets('Create account stays disabled until the box is ticked', (
      tester,
    ) async {
      final vm = _atNameStep(_backend([]));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            driverRegistrationViewModelProvider.overrideWith((ref) => vm),
          ],
          child: MaterialApp(
            theme: SkylineTheme.light(),
            home: const NameStep(),
          ),
        ),
      );

      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      check(button().onPressed).isNull();
      check(
        find.text('I agree to the ', findRichText: true).evaluate(),
      ).isNotEmpty();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      check(vm.hasConsented).isTrue();
      check(button().onPressed).isNotNull();
    });

    testWidgets('Terms and Privacy Policy open their pages', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: SkylineTheme.light(),
          home: Scaffold(
            body: ConsentCheckbox(
              value: false,
              onChanged: (_) {},
              openLink: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Terms'));
      await tester.tap(find.text('Privacy Policy'));

      check(opened).deepEquals([
        Uri.parse('https://apps.mojud.life/terms'),
        Uri.parse('https://apps.mojud.life/privacy'),
      ]);
    });
  });
}
