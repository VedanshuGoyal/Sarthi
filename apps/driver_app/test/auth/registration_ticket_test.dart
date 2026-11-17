import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/features/auth/data/driver_auth_repository.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/view_model/driver_registration_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A backend that reports every number as new, handing out [ticket] on
/// verify, and records each register request's body.
http.Client _backend(String? ticket, List<Map<String, dynamic>> registers) =>
    MockClient((request) async {
      if (request.url.path == '/driver/auth/otp/verify') {
        return http.Response(
          jsonEncode({'registered': false, 'registrationTicket': ?ticket}),
          200,
        );
      }
      registers.add(jsonDecode(request.body) as Map<String, dynamic>);
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
    });

Future<List<Map<String, dynamic>>> _signUp(String? ticket) async {
  final registers = <Map<String, dynamic>>[];
  final vm = DriverRegistrationViewModel(
    repository: DriverAuthRepository(client: _backend(ticket, registers)),
    initialStep: DriverRegistrationStep.otp,
    phoneNational: '9876543210',
  );
  addTearDown(vm.dispose);
  await vm.submitOtp('123456');
  check(vm.step).equals(DriverRegistrationStep.name);
  vm.setConsent(true);
  await vm.submitName('Ravi Kumar');
  check(vm.step).equals(DriverRegistrationStep.done);
  return registers;
}

void main() {
  group('registration ticket', () {
    test('the ticket from verifying is sent back when registering', () async {
      final registers = await _signUp('tkt-1');
      check(
        registers,
      ).single.has((b) => b['registrationTicket'], 'ticket').equals('tkt-1');
    });

    test('a server that sends no ticket gets none back', () async {
      final registers = await _signUp(null);
      check(registers.single.containsKey('registrationTicket')).isFalse();
    });

    test('DriverOtpResult reads the ticket for a new number', () {
      check(
        DriverOtpResult.fromJson({
          'registered': false,
          'registrationTicket': 'tkt-2',
        }).registrationTicket,
      ).equals('tkt-2');
      check(
        DriverOtpResult.fromJson({'registered': false}).registrationTicket,
      ).isNull();
    });
  });
}
