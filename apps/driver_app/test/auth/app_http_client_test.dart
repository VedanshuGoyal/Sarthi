import 'dart:async';

import 'package:checks/checks.dart';
import 'package:driver_app/core/services/app_http_client.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DriverAuthSession _session(String token) => DriverAuthSession(
  token: token,
  driver: Driver(id: 'd-$token', phoneE164: '+919800000001', name: 'Ravi'),
);

class _Sessions implements DriverSessionStorage {
  _Sessions(this._session);
  DriverAuthSession? _session;

  @override
  Future<DriverAuthSession?> read() async => _session;

  @override
  Future<void> write(DriverAuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

void main() {
  group('AppHttpClient', () {
    test('a request that never answers fails after the timeout', () async {
      final client = AppHttpClient(
        inner: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );

      await check(
        client.get(Uri.parse('http://api/driver/kyc')),
      ).throws<TimeoutException>();
    });

    test('a 401 to a signed-in request reports that session', () async {
      final rejected = <String>[];
      final client = AppHttpClient(
        inner: MockClient((_) async => http.Response('', 401)),
        onSessionRejected: rejected.add,
      );

      await client.get(
        Uri.parse('http://api/driver/kyc'),
        headers: {'Authorization': 'Bearer tok-1'},
      );
      // Signed-out calls (a wrong OTP is a 401 too) say nothing of a session.
      await client.post(Uri.parse('http://api/driver/auth/otp/verify'));

      check(rejected).deepEquals(['tok-1']);
    });
  });

  group('backendClientProvider', () {
    test('an expired session signs a driver mid-KYC out', () async {
      final container = ProviderContainer(
        overrides: [
          driverSessionStorageProvider.overrideWithValue(
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
      await container.read(driverAuthControllerProvider.future);

      await check(
        container.read(driverKycRepositoryProvider).load(),
      ).throws<KycException>();

      check(container.read(driverAuthControllerProvider).value).isNull();
    });

    test("a late 401 for the last driver doesn't sign out the next", () async {
      final answer = Completer<http.Response>();
      final container = ProviderContainer(
        overrides: [
          driverSessionStorageProvider.overrideWithValue(
            _Sessions(_session('tok-1')),
          ),
          httpClientProvider.overrideWithValue(
            MockClient((_) => answer.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(driverAuthControllerProvider.future);

      final loading = container.read(driverKycRepositoryProvider).load();
      final auth = container.read(driverAuthControllerProvider.notifier);
      await auth.signOut();
      await auth.signIn(_session('tok-2'));
      answer.complete(http.Response('', 401));
      await check(loading).throws<KycException>();

      check(
        container.read(driverAuthControllerProvider).value?.token,
      ).equals('tok-2');
    });
  });
}
