import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/features/home/view/driver_home_shell.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../documents/kyc_fakes.dart';
import '../rides/fakes.dart';

const _driver = Driver(id: 'd1', phoneE164: '+919800000001', name: 'Ravi');

class _Sessions implements DriverSessionStorage {
  DriverAuthSession? session = const DriverAuthSession(
    token: 'tok',
    driver: _driver,
  );

  @override
  Future<DriverAuthSession?> read() async => session;
  @override
  Future<void> write(DriverAuthSession session) async => this.session = session;
  @override
  Future<void> clear() async => session = null;
}

/// KYC that can't be loaded until [kyc] is set.
class _Kyc implements DriverKycRepository {
  DriverKyc? kyc;

  @override
  Future<DriverKyc> load() async =>
      kyc ??
      (throw const KycException(
        "Can't reach the server. Check your connection and try again.",
      ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Sessions sessions;
  late _Kyc kyc;
  late Directory tempDir;

  setUp(() {
    sessions = _Sessions();
    kyc = _Kyc();
    tempDir = Directory.systemTemp.createTempSync('kyc_gate');
    // Made up front: real async file I/O never settles under the widget
    // tester's fake clock.
    Directory('${tempDir.path}/${DocumentFileStore.folderName}').createSync();
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  List<Override> overrides(MemoryKycStatusStore store) => [
    httpClientProvider.overrideWithValue(
      MockClient((_) async => http.Response('{}', 404)),
    ),
    driverSessionStorageProvider.overrideWithValue(sessions),
    driverKycRepositoryProvider.overrideWithValue(kyc),
    kycStatusStoreProvider.overrideWithValue(store),
    pushServiceProvider.overrideWithValue(PushService.off()),
    locationServiceProvider.overrideWithValue(FakeLocationService()),
    ridesRepositoryProvider.overrideWithValue(FakeRidesRepository()),
  ];

  test(
    'the view model gets the stored status for the signed-in driver',
    () async {
      final container = ProviderContainer(
        overrides: overrides(MemoryKycStatusStore('d1', KycStatus.verified)),
      );
      addTearDown(container.dispose);
      await container.read(driverAuthControllerProvider.future);

      final vm = container.read(documentRegistrationViewModelProvider);
      check(vm.isRestoring).isTrue();
      while (vm.isRestoring) {
        await Future<void>.delayed(Duration.zero);
      }

      check(vm.isVerified).isTrue();
    },
  );

  Future<void> pumpApp(WidgetTester tester, MemoryKycStatusStore store) async {
    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(store),
          // The real one, with captures kept in a temp directory.
          documentRegistrationViewModelProvider.overrideWith(
            (ref) => DocumentRegistrationViewModel(
              repository: kyc,
              files: DocumentFileStore(directory: tempDir),
              statusStore: store,
              driverId: ref.watch(
                driverAuthControllerProvider.select(
                  (s) => s.valueOrNull?.driver.id,
                ),
              ),
            ),
          ),
        ],
        child: const SarthiDriverApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a verified driver gets Home even when KYC fails to load', (
    tester,
  ) async {
    await pumpApp(tester, MemoryKycStatusStore('d1', KycStatus.verified));

    check(find.byType(DriverHomeShell).evaluate()).length.equals(1);
  });

  testWidgets('without a known status, a failed load can be retried', (
    tester,
  ) async {
    await pumpApp(tester, MemoryKycStatusStore());

    check(
      find.text("Couldn't load your registration").evaluate(),
    ).length.equals(1);

    kyc.kyc = const DriverKyc();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    check(find.text('Complete your registration').evaluate()).length.equals(1);
  });

  testWidgets('a driver stuck on the failed load can log out', (tester) async {
    await pumpApp(tester, MemoryKycStatusStore());

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out').last); // the dialog's button
    await tester.pumpAndSettle();

    check(sessions.session).isNull();
    check(find.text('Start Driving').evaluate()).length.equals(1);
  });
}
