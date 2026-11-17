import 'dart:async';
import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/features/auth/data/driver_auth_repository.dart';
import 'package:driver_app/features/auth/view_model/driver_registration_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A backend where +919876543210 is an existing driver; verifying waits on
/// [verifyGate] when one is given, and counts into [verifies].
http.Client _backend({Completer<void>? verifyGate, List<int>? verifies}) =>
    MockClient((request) async {
      switch (request.url.path) {
        case '/driver/auth/otp':
          return http.Response('', 202);
        case '/driver/auth/otp/verify':
          verifies?.add(1);
          await verifyGate?.future;
          return http.Response(
            jsonEncode({
              'registered': true,
              'token': 'tok-driver',
              'driver': {
                'id': 'd1',
                'phoneE164': '+919876543210',
                'name': 'Ravi Kumar',
              },
            }),
            200,
          );
      }
      return http.Response('not found', 404);
    });

void main() {
  group('DriverRegistrationViewModel', () {
    test('a second verify while one is in flight is ignored', () async {
      // The keyboard's "done" key stays live under the disabled button.
      final gate = Completer<void>();
      final verifies = <int>[];
      final vm = DriverRegistrationViewModel(
        repository: DriverAuthRepository(
          client: _backend(verifyGate: gate, verifies: verifies),
        ),
      );
      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();
      check(vm.step).equals(DriverRegistrationStep.otp);

      final first = vm.submitOtp(DriverAuthRepository.devOtp);
      final second = vm.submitOtp(DriverAuthRepository.devOtp);
      gate.complete();
      await Future.wait([first, second]);

      check(verifies).length.equals(1);
      check(vm.step).equals(DriverRegistrationStep.done);
      check(vm.errorText).isNull();
      vm.dispose();
    });

    test(
      'signing in disposes the flow mid-request without a notify after',
      () async {
        // Signing in swaps the registration screen out, which disposes this
        // autoDispose view model before the request's own tail runs.
        late final DriverRegistrationViewModel vm;
        vm = DriverRegistrationViewModel(
          repository: DriverAuthRepository(client: _backend()),
          onSignedIn: (_) async => vm.dispose(),
        );
        vm.onPhoneChanged('9876543210');
        await vm.submitPhone();

        await vm.submitOtp(DriverAuthRepository.devOtp);
        check(vm.step).equals(DriverRegistrationStep.done);
      },
    );
  });
}
