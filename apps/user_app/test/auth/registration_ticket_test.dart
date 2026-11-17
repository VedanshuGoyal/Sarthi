import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';
import 'package:user_app/features/auth/domain/auth_session.dart';
import 'package:user_app/features/auth/view_model/registration_view_model.dart';

/// A backend that reports every number as new, handing out [ticket] on
/// verify, and records each register request's body.
http.Client _backend(String? ticket, List<Map<String, dynamic>> registers) =>
    MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path == '/auth/otp/verify') {
        return http.Response(
          jsonEncode({'registered': false, 'registrationTicket': ?ticket}),
          200,
        );
      }
      registers.add(body);
      return http.Response(
        jsonEncode({
          'registered': true,
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

Future<List<Map<String, dynamic>>> _signUp(String? ticket) async {
  final registers = <Map<String, dynamic>>[];
  final vm = RegistrationViewModel(
    repository: AuthRepository(client: _backend(ticket, registers)),
    initialStep: RegistrationStep.otp,
    phoneNational: '9876543210',
  );
  addTearDown(vm.dispose);
  await vm.submitOtp('123456');
  check(vm.step).equals(RegistrationStep.profile);
  vm
    ..onDateOfBirthChanged(DateTime(2000, 1, 1))
    ..onConsentChanged(true);
  await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');
  check(vm.step).equals(RegistrationStep.done);
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

    test('OtpResult reads the ticket for a new number', () {
      check(
        OtpResult.fromJson({
          'registered': false,
          'registrationTicket': 'tkt-2',
        }).registrationTicket,
      ).equals('tkt-2');
      check(
        OtpResult.fromJson({'registered': false}).registrationTicket,
      ).isNull();
    });
  });
}
