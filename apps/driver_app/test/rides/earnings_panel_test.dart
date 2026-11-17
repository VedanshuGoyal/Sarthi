import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/rides/data/rides_repository.dart';
import 'package:driver_app/features/rides/domain/payout.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/features/rides/view/earnings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'fakes.dart';

const _driver = Driver(
  id: 'd1',
  phoneE164: '+919800000001',
  name: 'Ravi Kumar',
);

const _emptyPayoutsBody =
    'Each transfer MOJUD makes to your bank is listed here with its '
    'reference.';

void main() {
  late FakeRidesRepository repo;

  setUp(() => repo = FakeRidesRepository());

  Future<void> pump(WidgetTester tester, {double width = 1080}) async {
    tester.view.physicalSize = Size(width, 4400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ridesRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          driverSessionStorageProvider.overrideWithValue(_SessionStorage()),
        ],
        child: MaterialApp(
          theme: SkylineTheme.light(),
          home: const EarningsPanel(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the driver\'s share beside each window and the payouts', (
    tester,
  ) async {
    repo
      ..summary = const Earnings(
        today: EarningsPeriod(farePaise: 34000, rides: 1, netPaise: 29580),
        week: EarningsPeriod(farePaise: 240000, rides: 8, netPaise: 208800),
        month: EarningsPeriod(farePaise: 240000, rides: 8, netPaise: 208800),
        total: EarningsPeriod(farePaise: 300000, rides: 10, netPaise: 261000),
      )
      ..payoutList = [
        Payout(
          id: 'p1',
          amountPaise: 13050,
          rides: 2,
          reference: 'UTR123',
          createdAt: DateTime(2026, 11, 10, 12),
        ),
      ];
    await pump(tester);

    check(find.text('₹340').evaluate()).isNotEmpty(); // today's gross
    check(find.text('₹296 yours after commission').evaluate()).length.equals(1);
    check(find.text('₹2,400').evaluate()).length.equals(2); // week, month
    check(find.text('₹2,088 yours').evaluate()).length.equals(2);
    check(find.text('₹2,610 yours').evaluate()).length.equals(1);

    check(find.text('Payouts').evaluate()).isNotEmpty();
    check(find.text('₹131').evaluate()).isNotEmpty();
    check(find.text('Ref UTR123').evaluate()).isNotEmpty();
    check(find.textContaining('2 trips · ').evaluate()).isNotEmpty();
    check(find.text(_emptyPayoutsBody).evaluate()).isEmpty();
  });

  testWidgets('an older server: gross only, and no payouts yet', (
    tester,
  ) async {
    repo.summary = const Earnings(
      today: EarningsPeriod(farePaise: 34000, rides: 1),
      week: EarningsPeriod(farePaise: 58000, rides: 2),
    );
    await pump(tester, width: 1000); // phone width: the 2 + 1 tile grid

    check(find.text('₹340').evaluate()).isNotEmpty();
    check(find.text('₹580').evaluate()).isNotEmpty();
    check(find.textContaining('yours').evaluate()).isEmpty();
    check(find.text('Payouts').evaluate()).isNotEmpty();
    check(find.text(_emptyPayoutsBody).evaluate()).length.equals(1);
  });

  testWidgets('payouts that fail to load leave the section out', (
    tester,
  ) async {
    repo
      ..summary = const Earnings(
        today: EarningsPeriod(farePaise: 34000, rides: 1),
      )
      ..payoutsFailure = const RidesException('payouts down');
    await pump(tester);

    check(find.text('₹340').evaluate()).isNotEmpty();
    check(find.text('Payouts').evaluate()).isEmpty();
    check(find.text('payouts down').evaluate()).isEmpty();
  });

  testWidgets('a cancellation fee counts in the money card but is no '
      'completed trip; an early-ended trip lists at its charge', (
    tester,
  ) async {
    repo
      ..summary = const Earnings(
        today: EarningsPeriod(farePaise: 20000, rides: 1),
        payments: DriverPayments(
          // The ₹200 early-ended trip and the ₹50 fee.
          awaitingCustomerPaise: 25000,
          awaitingCustomerRides: 2,
        ),
      )
      ..mine = [
        ride(
          id: 'fee',
          status: 'cancelled',
          cancelledBy: 'customer',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
        ),
        ride(
          id: 'ended',
          status: 'completed',
          farePaise: 20000,
          bookedFarePaise: 34000,
          paymentStatus: 'due',
        ),
      ];
    // Wide enough for the ride screen the row opens.
    await pump(tester, width: 1800);

    check(tester.takeException()).isNull();
    check(find.text('Waiting for customers to pay').evaluate()).isNotEmpty();
    check(find.text('2 trips').evaluate()).isNotEmpty();
    check(find.text('₹250').evaluate()).isNotEmpty();
    // One completed trip — the early-ended one, at what it was charged.
    check(
      find.byType(ListTile).evaluate().where((e) {
        final tile = e.widget as ListTile;
        return tile.onTap != null;
      }),
    ).length.equals(1);
    check(find.textContaining('Awaiting payment').evaluate()).length.equals(1);
    check(find.text('₹200').evaluate()).length.equals(2); // today, the row
    check(find.text('₹50').evaluate()).isEmpty();

    // The row opens the trip.
    await tester.tap(find.textContaining('Awaiting payment'));
    await tester.pumpAndSettle();
    check(find.text('Customer ended the trip early').evaluate()).isNotEmpty();
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
