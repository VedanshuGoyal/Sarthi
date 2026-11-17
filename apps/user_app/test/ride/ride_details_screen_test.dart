import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/activity_panel.dart';
import 'package:user_app/features/ride/view/ride_details_screen.dart';
import 'package:user_app/features/ride/view/widgets/cancel_ride_sheet.dart';
import 'package:user_app/features/ride/view/widgets/receipt_card.dart';
import 'package:user_app/features/ride/view/widgets/star_rating.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';

import '../support/fake_booking_server.dart';

/// Pumps [home] (the details screen of `b1` by default) over [server], with
/// the list loaded as Activity would have it.
Future<void> _pump(
  WidgetTester tester,
  FakeBookingServer server, {
  Widget home = const RideDetailsScreen(bookingId: 'b1'),
  bool settle = true,
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

/// Whether [text] is on the receipt itself (the trip details card has a
/// "Fare" row too).
bool _onReceipt(String text) => find
    .descendant(of: find.byType(ReceiptCard), matching: find.text(text))
    .evaluate()
    .isNotEmpty;

/// Opens the cancel sheet from the details screen.
Future<void> _openCancelSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Cancel ride'));
  await tester.pump();
  await tester.tap(find.text('Cancel ride'));
  await tester.pumpAndSettle();
}

/// Picks [reason] in the open cancel sheet and taps its confirm button,
/// labelled [confirm].
Future<void> _confirmCancel(
  WidgetTester tester, {
  String reason = 'Plans changed',
  String confirm = 'Cancel ride',
}) async {
  await tester.ensureVisible(find.text(reason));
  await tester.pump();
  await tester.tap(find.text(reason));
  await tester.pumpAndSettle();
  final button = find.widgetWithText(FilledButton, confirm);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

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

  group('payment', () {
    testWidgets('a paid ride shows its receipt', (tester) async {
      await _pump(
        tester,
        FakeBookingServer([
          bookingJson(
            status: 'completed',
            tripType: 'roundTrip',
            paymentStatus: 'paid',
            payment: {
              'mode': 'UPI_INTENT',
              'utr': '412345678901',
              'merchantOrderId':
                  'MOJUD_9f1c2a7b3d4e5f60718293a4b5c6d7e8_m3k9x2',
              'paidAt': '2030-10-26T08:00:00Z',
            },
            fareBreakdown: {'basePaise': 54000, 'nightPaise': 10000},
          ),
        ]),
      );
      await tester.ensureVisible(find.text('Receipt'));
      await tester.pump();
      for (final text in [
        'Receipt',
        'Fare',
        '₹640',
        'Base fare',
        '₹540',
        'Night surcharge',
        '₹100',
        'Paid via',
        'UPI',
        'Reference',
        '412345678901',
        'Order',
        'MOJUD_9f1c2a7b3d4e5f60718293a4b5c6d7e8_m3k9x2',
      ]) {
        check(because: text, _shows(text)).isTrue();
      }
      check(find.textContaining('by UPI').evaluate()).isEmpty();
    });

    testWidgets('a ride settled by hand says how, without a reference', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeBookingServer([
          bookingJson(
            status: 'completed',
            paymentStatus: 'paid',
            payment: {'mode': 'CASH', 'paidAt': '2030-10-26T08:00:00Z'},
          ),
        ]),
      );
      await tester.ensureVisible(find.text('Receipt'));
      await tester.pump();
      check(_shows('Cash')).isTrue();
      check(_shows('Reference')).isFalse();
      check(_shows('Order')).isFalse();
      check(_shows('Base fare')).isFalse();
    });

    testWidgets('the receipt fits a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final booking = MyBooking.tryParse(
        bookingJson(
          status: 'completed',
          paymentStatus: 'paid',
          payment: {
            'mode': 'NET_BANKING',
            'transactionId': 'T24111700012345678901234567890123456789',
            'merchantOrderId': 'MOJUD_9f1c2a7b3d4e5f60718293a4b5c6d7e8_m3k9x2',
            'paidAt': '2030-10-26T08:00:00Z',
          },
          fareBreakdown: {'basePaise': 54000, 'nightPaise': 10000},
        ),
      )!;
      await tester.pumpWidget(
        MaterialApp(
          theme: SkylineTheme.light(),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(Skyline.s20),
              children: [ReceiptCard(booking: booking)],
            ),
          ),
        ),
      );
      check(_shows('Net Banking')).isTrue();
      check(tester.takeException()).isNull();
    });

    testWidgets('a ride still due offers the Pay button, not a receipt', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeBookingServer([
          bookingJson(status: 'completed', paymentStatus: 'due'),
        ]),
        // Opening a due ride re-checks its payment in the background (a
        // spinner never settles under the fake clock), so don't settle.
        settle: false,
      );
      check(_shows('Pay ₹640 by UPI')).isTrue();
      check(_shows('Receipt')).isFalse();
    });
  });

  testWidgets('opening a due ride checks its payment once, not on every '
      'list refresh', (tester) async {
    final server = FakeBookingServer([
      bookingJson(status: 'completed', paymentStatus: 'due'),
    ]);
    final repo = server.repository();
    final bookings = MyBookingsViewModel(repository: repo);
    await tester.runAsync(bookings.load);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingRepositoryProvider.overrideWithValue(repo),
          myBookingsViewModelProvider.overrideWith((ref) => bookings),
        ],
        child: MaterialApp(
          theme: SkylineTheme.light(),
          home: const RideDetailsScreen(bookingId: 'b1'),
        ),
      ),
    );
    int syncs() =>
        server.requests.where((r) => r.url.path.endsWith('/sync')).length;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    check(syncs()).equals(1);

    // A list refresh (the 30 s poll, a push) doesn't start another check.
    await tester.runAsync(bookings.load);
    await tester.pump(const Duration(milliseconds: 100));
    check(syncs()).equals(1);
    check(_shows('Pay ₹640 by UPI')).isTrue();
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
      ).deepEquals({'reason': 'Car is in service', 'acceptFeePaise': 0});
      check(_shows('Ride cancelled')).isTrue();
      check(_shows('Cancelled by you · Car is in service')).isTrue();
      check(_shows('4 8 2 1')).isFalse();
      check(_shows('Your ride is cancelled.')).isTrue();
    });
  });

  group('cancellation fee', () {
    const freeLine =
        'Cancelling is free until the driver reaches your pickup. After '
        'that it costs ₹50.';
    const feeLine =
        'Ravi has reached your pickup, so cancelling now costs ₹50.';

    Map<String, dynamic> atPickup() =>
        bookingJson(status: 'arrived', otp: '4821', cancellationFeePaise: 5000);

    testWidgets('before the driver arrives, the sheet says it is free until '
        'then', (tester) async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      await _pump(tester, server);
      await _openCancelSheet(tester);

      check(_shows(freeLine)).isTrue();
      check(_shows(feeLine)).isFalse();
      check(
        find.widgetWithText(FilledButton, 'Cancel ride').evaluate(),
      ).isNotEmpty();
    });

    testWidgets('at the pickup, the sheet names the fee and cancelling '
        'leaves it to pay', (tester) async {
      final server = FakeBookingServer([atPickup()]);
      await _pump(tester, server);
      await _openCancelSheet(tester);

      check(_shows(feeLine)).isTrue();
      check(_shows(freeLine)).isFalse();
      await _confirmCancel(tester, confirm: 'Cancel and pay ₹50');

      final post = server.requests.firstWhere((r) => r.method == 'POST');
      check(post.url.path).equals('/me/bookings/b1/cancel');
      check(
        jsonDecode(post.body) as Map,
      ).deepEquals({'reason': 'Plans changed', 'acceptFeePaise': 5000});
      check(_shows('Ride cancelled')).isTrue();
      check(_shows('Your ride is cancelled. Please pay the ₹50 fee.')).isTrue();
      check(_shows('Pay the cancellation fee')).isTrue();
      check(_shows('Pay ₹50 by UPI')).isTrue();
    });

    testWidgets('a driver who arrives while the sheet is open gets the fee '
        'shown again before cancelling', (tester) async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      await _pump(tester, server);
      await _openCancelSheet(tester);
      check(_shows(freeLine)).isTrue();

      // The driver reaches the pickup before the customer confirms.
      server.bookings[0] = atPickup();
      await _confirmCancel(tester);

      // Not cancelled: asked again, with the fee and the same reason.
      check(server.bookings.single['status']).equals('arrived');
      check(_shows('Cancel this ride?')).isTrue();
      check(_shows(feeLine)).isTrue();
      check(_shows('Ride cancelled')).isFalse();
      final confirm = find.widgetWithText(FilledButton, 'Cancel and pay ₹50');
      check(tester.widget<FilledButton>(confirm).onPressed).isNotNull();

      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final cancels = [
        for (final r in server.requests)
          if (r.url.path.endsWith('/cancel')) jsonDecode(r.body) as Map,
      ];
      check(cancels).deepEquals([
        {'reason': 'Plans changed', 'acceptFeePaise': 0},
        {'reason': 'Plans changed', 'acceptFeePaise': 5000},
      ]);
      check(_shows('Ride cancelled')).isTrue();
      check(_shows('Pay ₹50 by UPI')).isTrue();
    });

    testWidgets('keeping the ride after seeing the fee sends nothing more', (
      tester,
    ) async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      await _pump(tester, server);
      await _openCancelSheet(tester);
      server.bookings[0] = atPickup();
      await _confirmCancel(tester);
      check(_shows(feeLine)).isTrue();

      await tester.ensureVisible(find.text('Keep my ride'));
      await tester.pump();
      await tester.tap(find.text('Keep my ride'));
      await tester.pumpAndSettle();

      check(
        server.requests.where((r) => r.url.path.endsWith('/cancel')),
      ).length.equals(1);
      check(_shows('Ravi is at your pickup')).isTrue();
    });

    testWidgets('a ride cancelled with its fee due offers the Pay button', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeBookingServer([
          bookingJson(
            status: 'cancelled',
            cancelReason: 'Plans changed',
            cancellationFeePaise: 5000,
            paymentStatus: 'due',
          ),
        ]),
        // Opening a due ride re-checks its payment; don't settle.
        settle: false,
      );
      check(_shows('Ride cancelled')).isTrue();
      check(_shows('Pay the cancellation fee')).isTrue();
      check(_shows('Pay ₹50 by UPI')).isTrue();
      check(_shows('Receipt')).isFalse();
      check(_shows('Cancel ride')).isFalse();
    });

    testWidgets('a paid fee has a receipt that reads as the fee', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeBookingServer([
          bookingJson(
            status: 'cancelled',
            cancellationFeePaise: 5000,
            paymentStatus: 'paid',
            payment: {'mode': 'UPI_INTENT', 'utr': '412345678901'},
            fareBreakdown: {'basePaise': 54000, 'nightPaise': 10000},
          ),
        ]),
      );
      await tester.ensureVisible(find.text('Receipt'));
      await tester.pump();
      check(_onReceipt('Cancellation fee')).isTrue();
      check(_onReceipt('₹50')).isTrue();
      check(_onReceipt('Fare')).isFalse();
      check(_onReceipt('Base fare')).isFalse();
      check(_onReceipt('₹640')).isFalse();
      check(_onReceipt('412345678901')).isTrue();
      check(find.textContaining('by UPI').evaluate()).isEmpty();
    });

    testWidgets('a ride cancelled for free shows nothing to pay', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeBookingServer([bookingJson(status: 'cancelled')]),
      );
      check(_shows('Pay the cancellation fee')).isFalse();
      check(find.textContaining('by UPI').evaluate()).isEmpty();
      check(_shows('Cancellation fee')).isFalse();
    });
  });

  group('cancel sheet copy', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      Map<String, dynamic> json, {
      int feePaise = 0,
      String? initialReason,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: SkylineTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CancelRideSheet(
              booking: MyBooking.tryParse(json)!,
              feePaise: feePaise,
              initialReason: initialReason,
            ),
          ),
        ),
      ),
    );

    testWidgets('at the pickup without a fee from the server, it is free', (
      tester,
    ) async {
      await pumpSheet(tester, bookingJson(status: 'arrived'));
      check(_shows('Cancelling is free.')).isTrue();
      check(find.textContaining('₹').evaluate()).isEmpty();
    });

    testWidgets('a request with no driver yet is free until one arrives', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        bookingJson(status: 'requested', withDriver: false),
      );
      check(
        _shows(
          'Cancelling is free until the driver reaches your pickup. After '
          'that it costs ₹50.',
        ),
      ).isTrue();
    });

    testWidgets('shown again, it keeps the reason given, typed ones too', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        bookingJson(status: 'arrived', cancellationFeePaise: 5000),
        feePaise: 5000,
        initialReason: 'Car is in service',
      );
      check(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
      ).equals('Car is in service');
      final confirm = find.widgetWithText(FilledButton, 'Cancel and pay ₹50');
      check(tester.widget<FilledButton>(confirm).onPressed).isNotNull();
    });
  });

  group('end trip early', () {
    testWidgets('only a trip in progress offers "End trip now"', (
      tester,
    ) async {
      for (final status in ['accepted', 'arrived', 'completed', 'cancelled']) {
        await _pump(tester, FakeBookingServer([bookingJson(status: status)]));
        check(because: status, _shows('End trip now')).isFalse();
        // A fresh ProviderScope for the next ride.
        await tester.pumpWidget(const SizedBox());
      }
      await _pump(
        tester,
        FakeBookingServer([bookingJson(status: 'in_progress')]),
      );
      check(_shows('End trip now')).isTrue();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the confirmation explains the charge, and keeping going '
        'sends nothing', (tester) async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      await _pump(tester, server);
      await tester.ensureVisible(find.text('End trip now'));
      await tester.pump();
      await tester.tap(find.text('End trip now'));
      await tester.pumpAndSettle();

      check(_shows('End trip now?')).isTrue();
      check(
        find.textContaining('by the hour for the time used').evaluate(),
      ).isNotEmpty();
      check(
        find
            .textContaining('Each started hour counts as a full hour')
            .evaluate(),
      ).isNotEmpty();
      check(_shows('Never more than your booked fare of ≈ ₹640.')).isTrue();

      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      check(_shows('End trip now?')).isFalse();
      check(server.requests.where((r) => r.method == 'POST')).isEmpty();
      check(_shows('On your trip')).isTrue();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ending the trip shows it charged for the time used, ready '
        'to pay', (tester) async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      await _pump(tester, server);
      await tester.ensureVisible(find.text('End trip now'));
      await tester.pump();
      await tester.tap(find.text('End trip now'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'End trip now'));
      await tester.pumpAndSettle();

      final post = server.requests.firstWhere((r) => r.method == 'POST');
      check(post.url.path).equals('/me/bookings/b1/end');
      check(_shows('Your trip has ended.')).isTrue();
      check(_shows('Trip ended early')).isTrue();
      check(_shows('Charged ₹240 for the time used (booked ₹640).')).isTrue();
      check(_shows('Pay for your trip')).isTrue();
      check(_shows('Pay ₹240 by UPI')).isTrue();
      check(_shows('End trip now')).isFalse();
      check(_shows('Booked fare')).isTrue();
    });

    testWidgets('a trip that already ended says so', (tester) async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      await _pump(tester, server);
      await tester.ensureVisible(find.text('End trip now'));
      await tester.pump();
      await tester.tap(find.text('End trip now'));
      await tester.pumpAndSettle();
      // The driver ends it before the customer confirms.
      server.bookings[0] = bookingJson(status: 'completed');
      await tester.tap(find.widgetWithText(FilledButton, 'End trip now'));
      await tester.pumpAndSettle();

      check(_shows("This trip isn't in progress any more.")).isTrue();
      check(_shows('Trip completed')).isTrue();
      check(_shows('End trip now')).isFalse();
    });

    testWidgets('a paid trip ended early reads as the time used on its '
        'receipt', (tester) async {
      await _pump(
        tester,
        FakeBookingServer([
          bookingJson(
            status: 'completed',
            farePaise: 24000,
            bookedFarePaise: 64000,
            paymentStatus: 'paid',
            payment: {'mode': 'UPI_INTENT'},
            // The booked fare's parts: they don't explain the charge.
            fareBreakdown: {'basePaise': 54000, 'nightPaise': 10000},
          ),
        ]),
      );
      await tester.ensureVisible(find.text('Receipt'));
      await tester.pump();
      check(_onReceipt('Fare for the time used')).isTrue();
      check(_onReceipt('₹240')).isTrue();
      check(_onReceipt('Booked fare')).isTrue();
      check(_onReceipt('₹640')).isTrue();
      check(_onReceipt('Base fare')).isFalse();
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

  testWidgets('Activity cards show a fee that needs paying, and a trip '
      'ended early', (tester) async {
    await _pump(
      tester,
      FakeBookingServer([
        bookingJson(
          status: 'completed',
          farePaise: 24000,
          bookedFarePaise: 64000,
          myRating: {'stars': 5},
        ),
        bookingJson(
          id: 'b2',
          status: 'cancelled',
          cancelReason: 'Plans changed',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
          scheduledAt: '2030-10-20T05:00:00Z',
        ),
        bookingJson(
          id: 'b3',
          status: 'cancelled',
          cancellationFeePaise: 5000,
          paymentStatus: 'paid',
          scheduledAt: '2030-10-19T05:00:00Z',
        ),
      ]),
      home: const ActivityPanel(),
    );
    await tester.tap(find.text('Completed · 3'));
    await tester.pumpAndSettle();

    check(
      _shows('Ended early. Charged ₹240 for the time used (booked ₹640).'),
    ).isTrue();
    check(find.text('Cancellation fee').evaluate()).length.equals(2);
    check(find.text('Paid').evaluate()).length.equals(1);
    // Only the unpaid fee asks to be paid.
    check(find.textContaining('by UPI').evaluate()).length.equals(1);

    await tester.tap(find.text('Pay ₹50 by UPI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    check(find.byType(RideDetailsScreen).evaluate()).isNotEmpty();
    check(_shows('Pay the cancellation fee')).isTrue();
  });
}
