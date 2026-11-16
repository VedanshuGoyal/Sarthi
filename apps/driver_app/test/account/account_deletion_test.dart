import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/features/account/view/delete_account_button.dart';
import 'package:driver_app/features/account/view_model/account_deletion_view_model.dart';
import 'package:driver_app/features/auth/data/driver_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// A backend answering `DELETE /driver/account` with [status] and [body],
/// recording each request.
DriverAuthRepository _repository(
  int status, {
  Map<String, dynamic>? body,
  List<http.Request>? requests,
}) => DriverAuthRepository(
  tokenGetter: () => 'tok-driver',
  client: MockClient((request) async {
    requests?.add(request);
    if (request.method == 'DELETE' && request.url.path == '/driver/account') {
      return http.Response(body == null ? '' : jsonEncode(body), status);
    }
    return http.Response('not found', 404);
  }),
);

const _busy = {
  'error': 'Finish your ride in progress before deleting your account.',
  'code': 'account_busy',
};

void main() {
  group('DriverAuthRepository.deleteAccount', () {
    test('sends DELETE /driver/account with the bearer token', () async {
      final requests = <http.Request>[];
      await _repository(
        200,
        body: {'status': 'erased'},
        requests: requests,
      ).deleteAccount();

      check(requests).length.equals(1);
      check(requests.single.method).equals('DELETE');
      check(
        requests.single.headers['Authorization'],
      ).equals('Bearer tok-driver');
    });

    test('a 409 account_busy carries the server reason', () async {
      await check(
        _repository(409, body: _busy).deleteAccount(),
      ).throws<AccountBusyException>(
        (e) => e.has((e) => e.message, 'message').equals(_busy['error']!),
      );
    });

    test('a 401 is a session expiry', () async {
      await check(
        _repository(
          401,
          body: {'error': 'invalid or expired session'},
        ).deleteAccount(),
      ).throws<SessionExpiredException>();
    });

    test('a 401 with an OTP code is not a session expiry', () async {
      // Registration's "verify again" answer is also a 401.
      final repo = DriverAuthRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'your verification expired; verify your number again',
              'code': 'otp_not_verified',
            }),
            401,
          ),
        ),
      );
      await check(
        repo.register(phoneE164: '+919876543210', name: 'Ravi'),
      ).throws<AuthException>(
        (e) => e.has((e) => e is SessionExpiredException, 'expiry').isFalse(),
      );
    });

    test('anything else is a plain AuthException', () async {
      await check(
        _repository(
          500,
          body: {'error': 'something went wrong'},
        ).deleteAccount(),
      ).throws<AuthException>(
        (e) =>
            e.has((e) => e.message, 'message').equals('something went wrong'),
      );
    });
  });

  group('AccountDeletionViewModel', () {
    test('a deleted account runs the sign-out tidy-up', () async {
      var tidied = 0;
      final vm = AccountDeletionViewModel(
        repository: _repository(200, body: {'status': 'erased'}),
        onDeleted: () async => tidied++,
      );

      check(await vm.deleteAccount()).isTrue();
      check(tidied).equals(1);
      check(vm.error).isNull();
      check(vm.isDeleting).isFalse();
    });

    test('a refusal shows the server reason and stays signed in', () async {
      var tidied = 0;
      final vm = AccountDeletionViewModel(
        repository: _repository(409, body: _busy),
        onDeleted: () async => tidied++,
      );

      check(await vm.deleteAccount()).isFalse();
      check(tidied).equals(0);
      check(vm.error).equals(_busy['error']);
      check(vm.isDeleting).isFalse();
    });

    test('an expired session says so', () async {
      final vm = AccountDeletionViewModel(
        repository: _repository(401, body: {'error': 'invalid'}),
        onDeleted: () async {},
      );

      check(await vm.deleteAccount()).isFalse();
      check(vm.error).isNotNull().contains('session has ended');
    });

    test('a network failure is a retryable error', () async {
      final vm = AccountDeletionViewModel(
        repository: DriverAuthRepository(
          client: MockClient((_) async => throw http.ClientException('down')),
        ),
        onDeleted: () async {},
      );

      check(await vm.deleteAccount()).isFalse();
      check(vm.error).isNotNull().contains("Can't reach the server");
    });
  });

  testWidgets('the confirmation explains what is deleted and what is kept', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: SkylineTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await showDialog<bool>(
              context: context,
              builder: (_) => const DeleteAccountDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    check(find.text('Delete your account?').evaluate()).isNotEmpty();
    check(
      find
          .textContaining('Records of rides you drove and payments are kept')
          .evaluate(),
    ).isNotEmpty();
    check(
      find
          .textContaining('Earnings not yet paid out are still owed to you')
          .evaluate(),
    ).isNotEmpty();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    check(answer).equals(false);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
    await tester.pumpAndSettle();
    check(answer).equals(true);
  });
}
