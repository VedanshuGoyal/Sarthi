import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';
import 'package:user_app/features/profile/profile_providers.dart';
import 'package:user_app/features/profile/view/widgets/delete_account_button.dart';
import 'package:user_app/features/profile/view_model/account_deletion_view_model.dart';

/// A server answering `DELETE /me/account` with [status] and [body],
/// recording what it was sent.
http.Client _server(
  int status, [
  Map<String, dynamic>? body,
  List<http.Request>? sent,
]) => MockClient((request) async {
  sent?.add(request);
  return http.Response(body == null ? '' : jsonEncode(body), status);
});

AccountDeletionViewModel _vm(http.Client client, {List<String>? events}) =>
    AccountDeletionViewModel(
      repository: AuthRepository(client: client, tokenGetter: () => 'tok-1'),
      onDeleted: () async => events?.add('signed out'),
    );

void main() {
  group('AuthRepository.deleteAccount', () {
    test('sends DELETE /me/account with the session token', () async {
      final sent = <http.Request>[];
      await AuthRepository(
        client: _server(200, {'status': 'erased'}, sent),
        baseUrl: 'https://api.example.test',
        tokenGetter: () => 'tok-1',
      ).deleteAccount();

      check(sent).single
        ..has((r) => r.method, 'method').equals('DELETE')
        ..has(
          (r) => r.url.toString(),
          'url',
        ).equals('https://api.example.test/me/account')
        ..has(
          (r) => r.headers['Authorization'],
          'Authorization',
        ).equals('Bearer tok-1');
    });

    test('a ride under way maps to AccountBusyException', () async {
      final repo = AuthRepository(
        client: _server(409, {
          'error': 'Finish your ride in progress first.',
          'code': 'account_busy',
        }),
      );
      await check(repo.deleteAccount()).throws<AccountBusyException>();
    });

    test('a rejected session maps to SessionExpiredException', () async {
      final repo = AuthRepository(client: _server(401, {'error': 'nope'}));
      await check(repo.deleteAccount()).throws<SessionExpiredException>();
    });
  });

  group('AccountDeletionViewModel', () {
    test('signs out once the server has erased the account', () async {
      final events = <String>[];
      final vm = _vm(_server(200, {'status': 'erased'}), events: events);

      check(await vm.deleteAccount()).isTrue();
      check(events).deepEquals(['signed out']);
      check(vm.errorText).isNull();
      check(vm.isDeleting).isFalse();
    });

    test(
      "a refusal keeps the customer signed in with the server's reason",
      () async {
        final events = <String>[];
        final vm = _vm(
          _server(409, {
            'error': 'A completed ride is still unpaid.',
            'code': 'account_busy',
          }),
          events: events,
        );

        check(await vm.deleteAccount()).isFalse();
        check(events).isEmpty();
        check(vm.errorText).equals('A completed ride is still unpaid.');
        check(vm.isDeleting).isFalse();
      },
    );

    test('an expired session says so and does not sign out itself', () async {
      final events = <String>[];
      final vm = _vm(_server(401, {'error': 'x'}), events: events);

      check(await vm.deleteAccount()).isFalse();
      check(events).isEmpty();
      check(vm.errorText).equals(const SessionExpiredException().message);
    });

    test('a server failure keeps the account with a generic error', () async {
      final events = <String>[];
      final vm = _vm(_server(500), events: events);

      check(await vm.deleteAccount()).isFalse();
      check(events).isEmpty();
      check(vm.errorText).isNotNull().contains('try again');
    });

    test('a second tap while deleting is ignored', () async {
      final sent = <http.Request>[];
      final vm = _vm(_server(200, {'status': 'erased'}, sent));

      final first = vm.deleteAccount();
      check(vm.isDeleting).isTrue();
      check(await vm.deleteAccount()).isFalse();
      check(await first).isTrue();
      check(sent).length.equals(1);
    });
  });

  group('DeleteAccountButton', () {
    Future<List<String>> pump(WidgetTester tester, http.Client client) async {
      final events = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountDeletionViewModelProvider.overrideWith(
              (ref) => _vm(client, events: events),
            ),
          ],
          child: MaterialApp(
            theme: SkylineTheme.light(),
            home: const Scaffold(body: Center(child: DeleteAccountButton())),
          ),
        ),
      );
      return events;
    }

    testWidgets('the confirmation explains what is deleted and what is kept', (
      tester,
    ) async {
      final events = await pump(tester, _server(200, {'status': 'erased'}));

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      check(find.text('Delete your account?').evaluate()).isNotEmpty();
      check(find.text(deleteAccountExplanation).evaluate()).isNotEmpty();
      check(deleteAccountExplanation)
        ..contains('Records of past rides and payments are kept')
        ..contains("can't be undone");

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      check(events).isEmpty();
    });

    testWidgets('confirming deletes the account and signs out', (tester) async {
      final events = await pump(tester, _server(200, {'status': 'erased'}));

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await tester.pumpAndSettle();

      check(events).deepEquals(['signed out']);
    });

    testWidgets('a refusal is shown and nothing is signed out', (tester) async {
      final events = await pump(
        tester,
        _server(409, {
          'error': 'Your ride is in progress.',
          'code': 'account_busy',
        }),
      );

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await tester.pumpAndSettle();

      check(events).isEmpty();
      check(find.text('Your ride is in progress.').evaluate()).isNotEmpty();
    });
  });
}
