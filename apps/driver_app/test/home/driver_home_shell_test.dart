import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/home/view/driver_home_shell.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../rides/fakes.dart';

const _driver = Driver(
  id: 'd1',
  phoneE164: '+919800000001',
  name: 'Ravi Kumar',
);

void main() {
  late Directory tempDir;
  late FakeRidesRepository rides;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shell_test');
    rides = FakeRidesRepository()
      ..openRides = [ride(id: 'open-1')]
      ..summary = const Earnings(
        today: EarningsPeriod(farePaise: 34000, rides: 1),
        week: EarningsPeriod(farePaise: 58000, rides: 2),
      );
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ridesRepositoryProvider.overrideWithValue(rides),
          pushServiceProvider.overrideWithValue(PushService.off()),
          locationServiceProvider.overrideWithValue(
            const FakeLocationService(),
          ),
          driverSessionStorageProvider.overrideWithValue(_SessionStorage()),
          documentRegistrationViewModelProvider.overrideWith(
            (ref) => DocumentRegistrationViewModel(
              repository: _KycRepository(),
              files: DocumentFileStore(directory: tempDir),
            ),
          ),
        ],
        child: MaterialApp(
          theme: SkylineTheme.light(),
          home: const DriverHomeShell(driver: _driver),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('going on duty shows requests, and accepting books the ride', (
    tester,
  ) async {
    await pumpShell(tester);

    check(find.text('Ready to drive?').evaluate()).isNotEmpty();
    check(find.text("You're offline").evaluate()).isNotEmpty();
    check(find.text('₹340').evaluate()).isNotEmpty(); // today's earnings

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    check(find.text("You're on duty").evaluate()).isNotEmpty();
    check(find.text('Accept ride').evaluate()).isNotEmpty();
    check(find.text('700 m away').evaluate()).isNotEmpty();

    await tester.tap(find.text('Accept ride'));
    await tester.pumpAndSettle();

    check(rides.acted.single).equals(('open-1', RideAction.accept));
    check(find.text('Your next ride').evaluate()).isNotEmpty();
    check(find.text('No requests right now').evaluate()).isNotEmpty();

    // Stop the poll timer before the test ends.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
  });

  testWidgets('the four panels are reachable from the nav bar', (tester) async {
    rides.mine = [ride(id: 'mine', status: 'accepted')];
    await pumpShell(tester);

    await tester.tap(find.text('Rides'));
    await tester.pumpAndSettle();
    check(find.text('My rides').evaluate()).isNotEmpty();
    check(find.text('Upcoming · 1').evaluate()).isNotEmpty();

    await tester.tap(find.text('Earnings').last);
    await tester.pumpAndSettle();
    check(find.text("Today's earnings").evaluate()).isNotEmpty();
    check(find.text('₹580').evaluate()).isNotEmpty(); // this week

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    check(find.text('Documents under review').evaluate()).isNotEmpty();
    check(find.text('HDFC0001234').evaluate()).isNotEmpty();
  });
}

class _SessionStorage implements DriverSessionStorage {
  @override
  Future<DriverAuthSession?> read() async =>
      const DriverAuthSession(token: 'tok', driver: _driver);

  @override
  Future<void> write(DriverAuthSession session) async {}

  @override
  Future<void> clear() async {}
}

class _KycRepository implements DriverKycRepository {
  @override
  Future<DriverKyc> load() async => const DriverKyc(
    status: KycStatus.submitted,
    fullName: 'Ravi Kumar',
    drivingLicenseNumber: 'DL0120190012345',
    aadhaarLast4: '9012',
    bankAccount: BankAccountSummary(
      accountHolderName: 'Ravi Kumar',
      accountNumberLast4: '2345',
      ifscCode: 'HDFC0001234',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
