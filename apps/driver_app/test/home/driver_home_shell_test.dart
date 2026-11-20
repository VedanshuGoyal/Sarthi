import 'dart:async';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/core/refresh_throttle.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/home/view/driver_home_shell.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/features/rides/view/ride_detail_screen.dart';
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
  late _KycRepository kyc;
  late _FakePush push;

  /// The view models' clock, which tests move on by hand.
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 11, 21, 9);
    tempDir = Directory.systemTemp.createTempSync('shell_test');
    kyc = _KycRepository();
    push = _FakePush();
    rides = FakeRidesRepository()
      ..openRides = [ride(id: 'open-1')]
      ..summary = const Earnings(
        today: EarningsPeriod(farePaise: 34000, rides: 1),
        week: EarningsPeriod(farePaise: 58000, rides: 2),
      );
  });
  tearDown(() {
    push.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, {double width = 1080}) async {
    tester.view.physicalSize = Size(width, 4400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          ridesRepositoryProvider.overrideWithValue(rides),
          pushServiceProvider.overrideWithValue(push),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          driverSessionStorageProvider.overrideWithValue(_SessionStorage()),
          documentRegistrationViewModelProvider.overrideWith(
            (ref) => DocumentRegistrationViewModel(
              repository: kyc,
              files: _NoCaptures(tempDir),
              now: () => now,
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

  group('pushes while the app is open', () {
    /// Goes on duty, so a refresh of the requests feed would actually run.
    Future<void> goOnDuty(WidgetTester tester) async {
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      check(find.text("You're on duty").evaluate()).isNotEmpty();
    }

    Future<void> goOffDuty(WidgetTester tester) async {
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    }

    testWidgets('a bank account change re-reads KYC, not the feed', (
      tester,
    ) async {
      await pumpShell(tester);
      await goOnDuty(tester);
      final requests = rides.requestsCalls;
      final kycLoads = kyc.loads;

      push.arrive(const PushEvent(type: 'bank_account_changed'));
      await tester.pumpAndSettle();

      check(kyc.loads).equals(kycLoads + 1);
      check(rides.requestsCalls).equals(requests);

      // A request push still refreshes the feed.
      push.arrive(const PushEvent(type: 'ride_request', rideId: 'open-2'));
      await tester.pumpAndSettle();
      check(rides.requestsCalls).equals(requests + 1);
      check(kyc.loads).equals(kycLoads + 1);

      await goOffDuty(tester);
    });

    testWidgets('a push type from a newer server re-reads the feed and, '
        'naming a ride, the rides — and its tap opens Home', (tester) async {
      await pumpShell(tester);
      await goOnDuty(tester);
      await tester.tap(find.text('Rides'));
      await tester.pumpAndSettle();
      final requests = rides.requestsCalls;
      final loads = rides.myRidesCalls;
      final kycLoads = kyc.loads;

      push.arrive(const PushEvent(type: 'ride_rescheduled', rideId: 'r9'));
      await tester.pumpAndSettle();

      check(rides.requestsCalls).equals(requests + 1);
      check(rides.myRidesCalls).equals(loads + 1);
      check(kyc.loads).equals(kycLoads);

      // Without a ride, only the feed.
      push.arrive(const PushEvent(type: 'promo'));
      await tester.pumpAndSettle();
      check(rides.requestsCalls).equals(requests + 2);
      check(rides.myRidesCalls).equals(loads + 1);

      push.tap(const PushEvent(type: 'promo'));
      await tester.pumpAndSettle();
      check(find.text("You're on duty").evaluate()).isNotEmpty();

      await goOffDuty(tester);
    });

    testWidgets('a payout re-reads the earnings, not the feed', (tester) async {
      await pumpShell(tester);
      await goOnDuty(tester);
      final requests = rides.requestsCalls;
      final earnings = rides.earningsCalls;

      push.arrive(const PushEvent(type: 'payout_sent'));
      await tester.pumpAndSettle();

      check(rides.earningsCalls).equals(earnings + 1);
      check(rides.requestsCalls).equals(requests);

      await goOffDuty(tester);
    });

    testWidgets('a ride MOJUD assigned re-reads the rides and opens on tap', (
      tester,
    ) async {
      // Wide enough for the ride screen's step row.
      await pumpShell(tester, width: 1800);
      await goOnDuty(tester);
      final requests = rides.requestsCalls;
      final loads = rides.myRidesCalls;
      rides.mine = [ride(id: 'assigned', status: 'accepted')];

      push.arrive(const PushEvent(type: 'ride_assigned', rideId: 'assigned'));
      await tester.pumpAndSettle();

      check(rides.myRidesCalls).equals(loads + 1);
      check(rides.requestsCalls).equals(requests);
      check(find.byType(RideDetailScreen).evaluate()).isEmpty();

      push.tap(const PushEvent(type: 'ride_assigned', rideId: 'assigned'));
      await tester.pumpAndSettle();
      check(find.byType(RideDetailScreen).evaluate()).length.equals(1);
      check(rides.requestsCalls).equals(requests);

      Navigator.of(tester.element(find.byType(RideDetailScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await goOffDuty(tester);
    });

    testWidgets('a trip the customer ended early re-reads the rides and the '
        'earnings, and opens it completed on tap', (tester) async {
      rides.mine = [ride(id: 'trip', status: 'in_progress')];
      // Wide enough for the ride screen's step row.
      await pumpShell(tester, width: 1800);
      await goOnDuty(tester);
      check(find.text('Ride in progress').evaluate()).isNotEmpty();
      final requests = rides.requestsCalls;
      final loads = rides.myRidesCalls;
      final earnings = rides.earningsCalls;
      rides.mine = [
        ride(
          id: 'trip',
          status: 'completed',
          farePaise: 20000,
          bookedFarePaise: 34000,
          paymentStatus: 'due',
        ),
      ];

      push.arrive(const PushEvent(type: 'ride_ended_early', rideId: 'trip'));
      await tester.pumpAndSettle();

      check(rides.myRidesCalls).equals(loads + 1);
      check(rides.earningsCalls).equals(earnings + 1);
      check(rides.requestsCalls).equals(requests);
      check(find.text('Ride in progress').evaluate()).isEmpty();
      check(find.byType(RideDetailScreen).evaluate()).isEmpty();

      push.tap(const PushEvent(type: 'ride_ended_early', rideId: 'trip'));
      await tester.pumpAndSettle();
      check(find.byType(RideDetailScreen).evaluate()).length.equals(1);
      check(find.text('Customer ended the trip early').evaluate()).isNotEmpty();
      check(find.text('Complete trip').evaluate()).isEmpty();
      check(rides.requestsCalls).equals(requests);

      Navigator.of(tester.element(find.byType(RideDetailScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await goOffDuty(tester);
    });
  });

  group('coming back to the app', () {
    /// Backgrounds the app and brings it back, one lifecycle step at a time
    /// as the platform reports them.
    Future<void> leaveAndReturn(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('while on a trip re-reads the rides, which may have ended', (
      tester,
    ) async {
      rides.mine = [ride(id: 'trip', status: 'in_progress')];
      await pumpShell(tester);
      final loads = rides.myRidesCalls;
      rides.mine = [ride(id: 'trip', status: 'completed', bookedFarePaise: 1)];
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);

      check(rides.myRidesCalls).equals(loads + 1);
      check(find.text('Ride in progress').evaluate()).isEmpty();
    });

    testWidgets('holding no ride still re-reads the rides (MOJUD may have '
        'assigned one) and the KYC', (tester) async {
      await pumpShell(tester);
      final loads = rides.myRidesCalls;
      final kycLoads = kyc.loads;
      rides.mine = [ride(id: 'assigned', status: 'accepted')];
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);

      check(rides.myRidesCalls).equals(loads + 1);
      check(kyc.loads).equals(kycLoads + 1);
      check(find.text('Your next ride').evaluate()).isNotEmpty();
    });

    testWidgets('right after a read, or a quick second time, reads nothing', (
      tester,
    ) async {
      await pumpShell(tester);
      final loads = rides.myRidesCalls;
      final kycLoads = kyc.loads;

      // Just loaded: still fresh.
      await leaveAndReturn(tester);
      check(rides.myRidesCalls).equals(loads);
      check(kyc.loads).equals(kycLoads);

      now = now.add(const Duration(minutes: 1));
      await leaveAndReturn(tester);
      now = now.add(const Duration(seconds: 5));
      await leaveAndReturn(tester);
      check(rides.myRidesCalls).equals(loads + 1);
      check(kyc.loads).equals(kycLoads + 1);

      // Fresh again once the gap has passed.
      now = now.add(RefreshThrottle.defaultGap);
      await leaveAndReturn(tester);
      check(rides.myRidesCalls).equals(loads + 2);
    });

    testWidgets('a push just before coming back counts as the read', (
      tester,
    ) async {
      await pumpShell(tester);
      now = now.add(const Duration(minutes: 1));
      push.arrive(const PushEvent(type: 'ride_cancelled', rideId: 'r1'));
      await tester.pumpAndSettle();
      final loads = rides.myRidesCalls;

      await leaveAndReturn(tester);

      check(rides.myRidesCalls).equals(loads);
    });

    testWidgets('on duty, re-reports the driver and re-reads the feed', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final requests = rides.requestsCalls;
      final reports = rides.duty.length;
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);

      check(rides.requestsCalls).equals(requests + 1);
      check(rides.duty.length).equals(reports + 1);
      check(rides.duty.last).isTrue();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    });

    testWidgets('re-reads the earnings only while they are on screen', (
      tester,
    ) async {
      await pumpShell(tester);
      final earnings = rides.earningsCalls;
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);
      check(rides.earningsCalls).equals(earnings);

      await tester.tap(find.text('Earnings').last);
      await tester.pumpAndSettle();
      final opened = rides.earningsCalls;
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);
      check(rides.earningsCalls).equals(opened + 1);
    });

    testWidgets('with the Documents open from Account, the KYC is read once', (
      tester,
    ) async {
      kyc.status = KycStatus.verified;
      await pumpShell(tester);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      check(find.text("You're verified").evaluate()).isNotEmpty();
      final kycLoads = kyc.loads;
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);

      check(kyc.loads).equals(kycLoads + 1);
    });
  });
}

/// A [PushService] whose arrivals and taps the test sends.
class _FakePush extends PushService {
  _FakePush() : super.off();

  final _arrivalEvents = StreamController<PushEvent>.broadcast();
  final _tapEvents = StreamController<PushEvent>.broadcast();

  @override
  Stream<PushEvent> get arrivals => _arrivalEvents.stream;

  @override
  Stream<PushEvent> get taps => _tapEvents.stream;

  void arrive(PushEvent event) => _arrivalEvents.add(event);

  void tap(PushEvent event) => _tapEvents.add(event);

  void close() {
    _arrivalEvents.close();
    _tapEvents.close();
  }
}

/// No captures on the device, and no disk I/O — which never finishes under
/// the widget tester's fake clock, and would leave the KYC load (and with
/// it every later refresh) hanging.
class _NoCaptures extends DocumentFileStore {
  _NoCaptures(Directory directory) : super(directory: directory);

  @override
  Future<String?> pathFor(DocumentKind kind) async => null;

  @override
  Future<void> discard(DocumentKind kind) async {}

  @override
  Future<void> discardAll() async {}
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
  /// How many times the KYC record was read.
  int loads = 0;

  KycStatus status = KycStatus.submitted;

  @override
  Future<DriverKyc> load() async {
    loads++;
    return DriverKyc(
      status: status,
      fullName: _kyc.fullName,
      drivingLicenseNumber: _kyc.drivingLicenseNumber,
      aadhaarLast4: _kyc.aadhaarLast4,
      bankAccount: _kyc.bankAccount,
    );
  }

  static const _kyc = DriverKyc(
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
