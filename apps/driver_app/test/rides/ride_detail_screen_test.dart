import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/features/rides/view/ride_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'fakes.dart';

const _driver = Driver(id: 'd1', phoneE164: '+919800000001', name: 'Ravi Kumar');

void main() {
  late FakeRidesRepository repo;

  Future<void> pump(WidgetTester tester, Ride ride) async {
    // A tall, wide viewport: ListView only builds children near the
    // viewport (the rating card sits below several other cards), and a
    // narrower width overflows the step progress row.
    tester.view.physicalSize = const Size(1800, 4400);
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
          home: RideDetailScreen(ride: ride),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = FakeRidesRepository();
  });

  testWidgets('a cancelled ride shows the notice and no action bar', (
    tester,
  ) async {
    final cancelledRide = ride(
      id: 'r',
      status: 'cancelled',
      cancelledAt: '2026-10-25T08:00:00+05:30',
      cancelledBy: 'customer',
      cancelReason: 'Plans changed',
    );
    repo.mine = [cancelledRide];

    await pump(tester, cancelledRide);

    check(find.text('Cancelled by customer').evaluate()).isNotEmpty();
    check(find.textContaining('Plans changed').evaluate()).isNotEmpty();
    check(find.text('Accept ride').evaluate()).isEmpty();
    check(find.text("I've arrived at pickup").evaluate()).isEmpty();
    check(find.text('Complete trip').evaluate()).isEmpty();
  });

  testWidgets(
    'a completed ride with no rating shows the rating form, and submitting '
    'it shows the given stars',
    (tester) async {
      final completedRide = ride(id: 'r', status: 'completed');
      repo.mine = [completedRide];

      await pump(tester, completedRide);

      check(find.text('Rate your customer').evaluate()).isNotEmpty();
      check(find.text('Submit rating').evaluate()).isNotEmpty();

      // Tap the 4th star, then submit.
      final stars = find.byIcon(Icons.star_outline_rounded);
      await tester.tap(stars.at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit rating'));
      await tester.pumpAndSettle();

      check(repo.lastRating).equals((4, null));
      check(find.text('You rated 4★').evaluate()).isNotEmpty();
      check(find.text('Rate your customer').evaluate()).isEmpty();
    },
  );
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
