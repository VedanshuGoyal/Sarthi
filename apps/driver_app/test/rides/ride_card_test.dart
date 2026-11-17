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
}
