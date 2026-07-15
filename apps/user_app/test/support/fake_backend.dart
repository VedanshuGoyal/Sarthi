import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [MockClient] that emulates the Sarthi backend's auth endpoints so tests
/// exercise the real [AuthRepository] logic without a network or server.
///
/// Numbers in [registeredPhones] are treated as existing accounts: verifying
/// their OTP returns a logged-in session (`registered: true`) instead of
/// routing to registration.
http.Client fakeBackendClient({Set<String> registeredPhones = const {}}) {
  return MockClient((request) async {
    switch (request.url.path) {
      case '/auth/otp':
      case '/auth/otp/resend':
      case '/auth/logout':
        return http.Response('', 202);

      case '/auth/otp/verify':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['code'] != '123456') {
          return http.Response(
            jsonEncode({
              'error': 'incorrect verification code',
              'code': 'otp_incorrect',
            }),
            401,
          );
        }
        final phone = body['phoneE164'] as String;
        if (registeredPhones.contains(phone)) {
          // Returning customer — logged straight in.
          return http.Response(
            jsonEncode({
              'registered': true,
              'token': 'tok-existing',
              'user': _user(phone, name: 'Returning User'),
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'registered': false}), 200);

      case '/auth/register':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'token': 'tok-new',
            'user': _user(
              body['phoneE164'] as String,
              name: body['name'] as String,
              email: body['email'] as String,
              dateOfBirth: body['dateOfBirth'] as String,
            ),
          }),
          201,
        );

      default:
        return http.Response('not found', 404);
    }
  });
}

Map<String, dynamic> _user(
  String phone, {
  String name = 'Test User',
  String email = 'test@example.com',
  String dateOfBirth = '2000-01-01',
}) {
  return {
    'id': 'u1',
    'phoneE164': phone,
    'name': name,
    'email': email,
    'dateOfBirth': dateOfBirth,
  };
}
