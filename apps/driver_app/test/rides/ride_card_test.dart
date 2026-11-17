import 'package:checks/checks.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/view/widgets/ride_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, Ride ride) => tester.pumpWidget(
    MaterialApp(
      theme: SkylineTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: RideCard(ride: ride)),
      ),
    ),
  );

  testWidgets('a request card shows the whole area and says the address '
      'comes after accepting', (tester) async {
    await pump(tester, ride(approximate: true));

    // The area isn't cut to its first part like a full address would be.
    check(find.text('Saket, New Delhi').evaluate()).isNotEmpty();
    check(find.text('Exact address after you accept').evaluate()).isNotEmpty();
  });

  testWidgets('an accepted ride card shows the short address and no hint', (
    tester,
  ) async {
    await pump(tester, ride(status: 'accepted'));

    check(find.text('Connaught Place').evaluate()).isNotEmpty();
    check(find.text('Exact address after you accept').evaluate()).isEmpty();
  });

  testWidgets('a ride cancelled at the pickup shows the fee and where its '
      'payment stands', (tester) async {
    Ride cancelled(String status, {int? share}) => ride(
      status: 'cancelled',
      cancelledBy: 'customer',
      cancellationFeePaise: 5000,
      paymentStatus: status,
      sharePaise: share,
    );

    await pump(tester, cancelled('due'));
    check(
      find.text('Customer cancelled at the pickup').evaluate(),
    ).isNotEmpty();
    check(
      find.text('₹50 cancellation fee · Awaiting payment').evaluate(),
    ).isNotEmpty();

    await pump(tester, cancelled('paid', share: 4350));
    check(
      find
          .text('₹50 cancellation fee · Paid · your share ₹44 after commission')
          .evaluate(),
    ).isNotEmpty();

    await pump(tester, cancelled('paid_out', share: 4350));
    check(find.text('₹50 cancellation fee · Paid out').evaluate()).isNotEmpty();
  });

  testWidgets('a free cancellation shows no fee', (tester) async {
    await pump(tester, ride(status: 'cancelled', cancelledBy: 'customer'));

    check(find.text('Cancelled by customer').evaluate()).isNotEmpty();
    check(find.textContaining('cancellation fee').evaluate()).isEmpty();
  });

  testWidgets('a trip the customer ended early says what it was charged', (
    tester,
  ) async {
    await pump(
      tester,
      ride(status: 'completed', farePaise: 20000, bookedFarePaise: 34000),
    );

    check(find.text('₹200').evaluate()).isNotEmpty();
    check(
      find
          .text(
            'Customer ended the trip early · '
            'Charged ₹200 for the time used (booked ₹340)',
          )
          .evaluate(),
    ).isNotEmpty();

    // A trip that ran its course says nothing of the sort.
    await pump(tester, ride(status: 'completed'));
    check(find.textContaining('ended the trip early').evaluate()).isEmpty();
  });
}
