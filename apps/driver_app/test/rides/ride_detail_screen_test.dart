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

const _driver = Driver(
  id: 'd1',
  phoneE164: '+919800000001',
  name: 'Ravi Kumar',
);

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

  testWidgets(
    'an open request shows only the area, and no plate, until accepted',
    (tester) async {
      final request = ride(id: 'r', approximate: true);
      repo.openRides = [request];

      await pump(tester, request);

      check(find.text('Saket, New Delhi').evaluate()).isNotEmpty();
      check(find.text('DL01AB1234').evaluate()).isEmpty();
      check(find.textContaining('The exact address').evaluate()).isNotEmpty();
      check(find.text('Accept ride').evaluate()).isNotEmpty();
    },
  );

  testWidgets('waiting at the pickup: no-show waits for its time', (
    tester,
  ) async {
    final soon = DateTime.now().add(const Duration(minutes: 10));
    final waiting = ride(
      id: 'r',
      status: 'arrived',
      noShowAt: soon.toUtc().toIso8601String(),
    );
    repo.mine = [waiting];

    await pump(tester, waiting);

    check(find.text('Customer not here?').evaluate()).isNotEmpty();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'No-show'),
    );
    check(button.onPressed).isNull();
  });

  testWidgets('after the wait, the driver can close the ride as a no-show', (
    tester,
  ) async {
    final past = DateTime.now().subtract(const Duration(minutes: 1));
    final waiting = ride(
      id: 'r',
      status: 'arrived',
      noShowAt: past.toUtc().toIso8601String(),
    );
    repo.mine = [waiting];

    await pump(tester, waiting);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'No-show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close ride'));
    await tester.pumpAndSettle();

    check(repo.acted.last).equals(('r', RideAction.noShow));
    check(find.text("Customer didn't come").evaluate()).isNotEmpty();
    check(find.text('Customer not here?').evaluate()).isEmpty();
  });

  testWidgets("once the backend hides the customer's number, there's no "
      'call button', (tester) async {
    final json = rideJson(id: 'r', status: 'completed', withCustomer: true);
    (json['customer'] as Map<String, dynamic>)['phoneE164'] = '';
    final done = Ride.tryParse(json)!;
    repo.mine = [done];

    await pump(tester, done);

    check(find.text('Asha Kumari').evaluate()).isNotEmpty();
    check(find.text('Number hidden after the ride').evaluate()).isNotEmpty();
    check(find.byTooltip('Call customer').evaluate()).isEmpty();
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

  testWidgets('a ride the customer cancelled at the pickup shows the fee '
      'and its payment, not as the fare\'s', (tester) async {
    final cancelledRide = ride(
      id: 'r',
      status: 'cancelled',
      cancelledAt: '2026-10-25T08:00:00+05:30',
      cancelledBy: 'customer',
      cancelReason: 'Plans changed',
      cancellationFeePaise: 5000,
      paymentStatus: 'paid',
      sharePaise: 4350,
    );
    repo.mine = [cancelledRide];

    await pump(tester, cancelledRide);

    check(
      find.text('Customer cancelled at the pickup').evaluate(),
    ).isNotEmpty();
    check(find.text('Reason: Plans changed').evaluate()).isNotEmpty();
    check(find.text('₹50 cancellation fee').evaluate()).isNotEmpty();
    check(
      find.text('Paid · your share ₹44 after commission').evaluate(),
    ).isNotEmpty();
    // The booked fare isn't what was paid.
    check(find.text('trip fare').evaluate()).isNotEmpty();
    check(find.text('trip fare · paid').evaluate()).isEmpty();
    check(find.text('Rate your customer').evaluate()).isEmpty();
  });

  for (final (status, says) in [
    ('due', 'Awaiting payment'),
    ('paid_out', 'Paid out'),
  ]) {
    testWidgets('a cancellation fee that is $status says "$says"', (
      tester,
    ) async {
      final cancelledRide = ride(
        id: 'r',
        status: 'cancelled',
        cancelledBy: 'customer',
        cancellationFeePaise: 5000,
        paymentStatus: status,
      );
      repo.mine = [cancelledRide];
      await pump(tester, cancelledRide);

      check(find.text('₹50 cancellation fee').evaluate()).isNotEmpty();
      check(find.text(says).evaluate()).isNotEmpty();
    });
  }

  testWidgets('a trip the customer ended early shows the charge for the '
      'time used against the booked fare', (tester) async {
    final ended = ride(
      id: 'r',
      status: 'completed',
      farePaise: 20000,
      bookedFarePaise: 34000,
      paymentStatus: 'due',
    );
    repo.mine = [ended];

    await pump(tester, ended);

    check(find.text('Customer ended the trip early').evaluate()).isNotEmpty();
    check(
      find.text('Charged ₹200 for the time used (booked ₹340)').evaluate(),
    ).isNotEmpty();
    check(find.text('₹200').evaluate()).isNotEmpty();
    check(find.text('trip fare · awaiting payment').evaluate()).isNotEmpty();
  });

  group('a trip the customer ends while its screen is open', () {
    final onTrip = ride(id: 'r', status: 'in_progress');
    final ended = ride(
      id: 'r',
      status: 'completed',
      farePaise: 20000,
      bookedFarePaise: 34000,
      paymentStatus: 'due',
    );

    /// What the `ride_ended_early` push (or coming back to the app) does:
    /// re-read the rides.
    Future<void> reload(WidgetTester tester) async {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RideDetailScreen)),
      );
      repo.mine = [ended];
      await container.read(myRidesViewModelProvider).load();
      await tester.pumpAndSettle();
    }

    testWidgets('turns completed on the next reload, without the driver '
        'tapping Complete', (tester) async {
      repo.mine = [onTrip];
      await pump(tester, onTrip);
      check(find.text('Complete trip').evaluate()).isNotEmpty();

      await reload(tester);

      check(find.text('Complete trip').evaluate()).isEmpty();
      check(find.text('Completed').evaluate()).isNotEmpty(); // status chip
      check(find.text('Customer ended the trip early').evaluate()).isNotEmpty();
      check(find.text('Rate your customer').evaluate()).isNotEmpty();
      check(find.byType(SnackBar).evaluate()).isEmpty();
      check(repo.acted).isEmpty();
      check(tester.takeException()).isNull();
    });

    testWidgets('a Complete confirmed after it ended sends nothing and says '
        'what the customer pays', (tester) async {
      repo.mine = [onTrip];
      await pump(tester, onTrip);

      await tester.tap(find.text('Complete trip'));
      await tester.pumpAndSettle();
      check(find.text('Complete the trip?').evaluate()).isNotEmpty();

      // The customer ends it while the dialog is open.
      await reload(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Complete'));
      await tester.pumpAndSettle();

      check(repo.acted).isEmpty();
      check(
        find
            .text(
              'The customer ended the trip early. They can now pay ₹200 by '
              'UPI in their app.',
            )
            .evaluate(),
      ).isNotEmpty();
      check(find.text('Complete trip').evaluate()).isEmpty();
      check(find.text('Customer ended the trip early').evaluate()).isNotEmpty();
    });
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
