import 'dart:async';

import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/core/services/app_http_client.dart';
import 'package:user_app/features/auth/auth_controller.dart';
import 'package:user_app/features/auth/data/session_storage.dart';
import 'package:user_app/features/auth/domain/auth_session.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/ride_providers.dart';

AuthSession _session(String token) => AuthSession(
  token: token,
  user: AuthUser(
    id: 'u-$token',
    phoneE164: '+919876543210',
    name: 'Asha Sharma',
    email: 'asha@example.com',
    dateOfBirth: DateTime(1995),
  ),
);

class _Sessions implements SessionStorage {
  _Sessions(this._session);
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

void main() {
  group('AppHttpClient', () {
    test('a request that never answers fails after the timeout', () {
      fakeAsync((async) {
        final client = AppHttpClient(
          inner: MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 5),
        );
        Object? error;
        client
            .get(Uri.parse('http://api/me/bookings'))
            .then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(seconds: 4));
        check(error).isNull();
        async.elapse(const Duration(seconds: 2));
        check(error).isA<TimeoutException>();
      });
    });

    test('a 401 to a signed-in request reports that session', () async {
      final rejected = <String>[];
      final client = AppHttpClient(
        inner: MockClient((_) async => http.Response('', 401)),
        onSessionRejected: rejected.add,
      );

      await client.get(
        Uri.parse('http://api/me/bookings'),
        headers: {'Authorization': 'Bearer tok-1'},
      );
      // Signed-out calls (a wrong OTP is a 401 too) say nothing of a session.
      await client.post(Uri.parse('http://api/auth/otp/verify'));

      check(rejected).deepEquals(['tok-1']);
    });

    test('other statuses leave the session alone', () async {
      final rejected = <String>[];
      final client = AppHttpClient(
        inner: MockClient((_) async => http.Response('', 403)),
        onSessionRejected: rejected.add,
      );

      await client.get(
        Uri.parse('http://api/me/bookings'),
        headers: {'Authorization': 'Bearer tok-1'},
      );

      check(rejected).isEmpty();
    });
  });

  group('backendClientProvider', () {
    test('an expired session signs the customer out', () async {
      final container = ProviderContainer(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            _Sessions(_session('tok-1')),
          ),
          httpClientProvider.overrideWithValue(
            MockClient(
              (_) async =>
                  http.Response('{"error":"invalid or expired session"}', 401),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await check(
        container.read(bookingRepositoryProvider).myBookings(),
      ).throws<BookingSubmitException>();

      check(container.read(authControllerProvider).value).isNull();
    });

    test("a late 401 for the last account doesn't sign out the next", () async {
      final answer = Completer<http.Response>();
      final container = ProviderContainer(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            _Sessions(_session('tok-1')),
          ),
          httpClientProvider.overrideWithValue(
            MockClient((_) => answer.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      final loading = container.read(bookingRepositoryProvider).myBookings();
      final auth = container.read(authControllerProvider.notifier);
      await auth.signOut();
      await auth.signIn(_session('tok-2'));
      answer.complete(http.Response('', 401));
      await check(loading).throws<BookingSubmitException>();

      check(
        container.read(authControllerProvider).value?.token,
      ).equals('tok-2');
    });
  });
}
