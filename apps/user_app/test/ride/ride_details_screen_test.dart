import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/activity_panel.dart';
import 'package:user_app/features/ride/view/ride_details_screen.dart';
import 'package:user_app/features/ride/view/widgets/star_rating.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';

import '../support/fake_booking_server.dart';

/// Pumps [home] (the details screen of `b1` by default) over [server], with
/// the list loaded as Activity would have it.
Future<void> _pump(
  WidgetTester tester,
  FakeBookingServer server, {
  Widget home = const RideDetailsScreen(bookingId: 'b1'),
}) async {
  final repo = server.repository();
  final bookings = MyBookingsViewModel(repository: repo);
  await tester.runAsync(bookings.load);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(repo),
        myBookingsViewModelProvider.overrideWith((ref) => bookings),
      ],
      child: MaterialApp(theme: SkylineTheme.light(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  testWidgets('a request still looking for a driver can be cancelled', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeBookingServer([bookingJson(status: 'requested', withDriver: false)]),
    );
    check(_shows('Finding you a driver')).isTrue();
    check(_shows('Start code')).isFalse();
    check(_shows('Cancel ride')).isTrue();
    // The plan: every stop with its errand.
    check(_shows('Apollo Pharmacy')).isTrue();
    check(_shows('Collect the prescription')).isTrue();
    check(_shows('Est. duration')).isTrue();
  });

  testWidgets('an assigned ride shows the code, driver and rating', (
    tester,
  ) async {
    await _pump(tester, FakeBookingServer([bookingJson(otp: '4821')]));
    check(_shows('Ravi is your driver')).isTrue();
    check(_shows('4 8 2 1')).isTrue();
    check(_shows('★ 4.7 · 12 ratings')).isTrue();
    check(find.byTooltip('Call driver').evaluate()).isNotEmpty();
    check(_shows('DL01AB1234 · Sedan · Manual')).isTrue();
    check(_shows('Cancel ride')).isTrue();
    // Far from the start: not tracking yet.
    check(find.textContaining('location').evaluate()).isEmpty();
  });

  testWidgets('a ride on its trip tracks the driver and cannot be cancelled', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeBookingServer([bookingJson(status: 'in_progress', ratingCount: 0)]),
    );
    check(_shows('On your trip')).isTrue();
    // The server has no fix ({"location": null}); no map without a key.
    check(_shows("Waiting for your driver's location")).isTrue();
    check(_shows('New driver')).isTrue();
    check(_shows('Cancel ride')).isFalse();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a completed ride asks for stars and then shows them', (
    tester,
  ) async {
    final server = FakeBookingServer([bookingJson(status: 'completed')]);
    await _pump(tester, server);
    check(_shows('Rate your driver')).isTrue();
    check(_shows('Cancel ride')).isFalse();

    await tester.tap(find.byTooltip('4 stars'));
    await tester.enterText(find.byType(TextFormField), 'Smooth drive');
    await tester.pump();
    await tester.ensureVisible(find.text('Submit rating'));
    await tester.pump();
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();

    final post = server.requests.firstWhere((r) => r.method == 'POST');
    check(
      jsonDecode(post.body) as Map,
    ).deepEquals({'stars': 4, 'note': 'Smooth drive'});
    check(_shows('Rate your driver')).isFalse();
    check(_shows('You rated ')).isTrue();
    check(_shows('“Smooth drive”')).isTrue();
  });

  testWidgets('a rated ride shows the stars given', (tester) async {
    await _pump(
      tester,
      FakeBookingServer([
        bookingJson(
          status: 'completed',
          myRating: {'stars': 5, 'note': 'Great driver'},
        ),
      ]),
    );
    check(_shows('You rated ')).isTrue();
    check(tester.widget<StarRow>(find.byType(StarRow)).stars).equals(5);
    check(_shows('Rate your driver')).isFalse();
  });

  testWidgets('a cancelled ride says who cancelled and why', (tester) async {
    await _pump(
      tester,
      FakeBookingServer([
        bookingJson(status: 'cancelled', cancelReason: 'Plans changed'),
      ]),
    );
    check(_shows('Ride cancelled')).isTrue();
    check(_shows('Cancelled by you · Plans changed')).isTrue();
    // The timeline ends at the cancel.
    check(_shows('Cancelled by you')).isTrue();
    check(_shows('Cancel ride')).isFalse();
  });

  group('cancel sheet', () {
    testWidgets('warns about the driver, and keeping the ride sends nothing', (
      tester,
    ) async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      await _pump(tester, server);
      await tester.ensureVisible(find.text('Cancel ride'));
      await tester.pump();
      await tester.tap(find.text('Cancel ride'));
      await tester.pumpAndSettle();

      check(_shows('Cancel this ride?')).isTrue();
      check(find.textContaining('Ravi has accepted').evaluate()).isNotEmpty();
      for (final reason in ['Plans changed', 'Found another option', 'Other']) {
        check(_shows(reason)).isTrue();
      }
      // Confirming needs a reason.
      final confirm = find.widgetWithText(FilledButton, 'Cancel ride');
      check(tester.widget<FilledButton>(confirm).onPressed).isNull();

      await tester.ensureVisible(find.text('Keep my ride'));
      await tester.pump();
      await tester.tap(find.text('Keep my ride'));
      await tester.pumpAndSettle();
      check(_shows('Cancel this ride?')).isFalse();
      check(server.requests.where((r) => r.method == 'POST')).isEmpty();
      check(_shows('4 8 2 1')).isTrue();
    });

    testWidgets('"Other" takes free text, and confirming cancels the ride', (
      tester,
    ) async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      await _pump(tester, server);
      await tester.ensureVisible(find.text('Cancel ride'));
      await tester.pump();
      await tester.tap(find.text('Cancel ride'));
      await tester.pumpAndSettle();

      check(find.byType(TextField).evaluate()).isEmpty();
      await tester.ensureVisible(find.text('Other'));
      await tester.pump();
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Car is in service');
      await tester.pump();
      final confirm = find.widgetWithText(FilledButton, 'Cancel ride');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final post = server.requests.firstWhere((r) => r.method == 'POST');
      check(post.url.path).equals('/me/bookings/b1/cancel');
      check(
        jsonDecode(post.body) as Map,
      ).deepEquals({'reason': 'Car is in service'});
      check(_shows('Ride cancelled')).isTrue();
      check(_shows('Cancelled by you · Car is in service')).isTrue();
      check(_shows('4 8 2 1')).isFalse();
      check(_shows('Your ride is cancelled.')).isTrue();
    });
  });

  testWidgets('tapping a ride in Activity opens its details', (tester) async {
    await _pump(
      tester,
      FakeBookingServer([bookingJson(otp: '4821')]),
      home: const ActivityPanel(),
    );
    await tester.tap(find.text('Multi-Stop'));
    await tester.pumpAndSettle();
    check(find.byType(RideDetailsScreen).evaluate()).isNotEmpty();
    check(_shows('Timeline')).isTrue();
  });

  testWidgets('Activity cards offer a rating, or show the stars given', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeBookingServer([
        bookingJson(status: 'completed'),
        bookingJson(
          id: 'b2',
          status: 'completed',
          myRating: {'stars': 3},
          scheduledAt: '2030-10-20T05:00:00Z',
        ),
        bookingJson(
          id: 'b3',
          status: 'cancelled',
          cancelReason: 'Booked by mistake',
          scheduledAt: '2030-10-19T05:00:00Z',
        ),
      ]),
      home: const ActivityPanel(),
    );
    await tester.tap(find.text('Completed · 3'));
    await tester.pumpAndSettle();
    check(_shows('Rate your trip')).isTrue();
    check(tester.widget<StarRow>(find.byType(StarRow)).stars).equals(3);
    check(_shows('Cancelled by you · Booked by mistake')).isTrue();

    // "Rate your trip" opens the rating sheet.
    await tester.tap(find.text('Rate your trip'));
    await tester.pumpAndSettle();
    check(_shows('How was your trip with Ravi?')).isTrue();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    check(_shows('How was your trip with Ravi?')).isFalse();
  });
}
