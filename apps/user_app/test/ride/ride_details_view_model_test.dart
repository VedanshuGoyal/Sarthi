import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/upi_checkout.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/payment_checkout.dart';
import 'package:user_app/features/ride/ride_labels.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/features/ride/view_model/ride_details_view_model.dart';
import 'package:user_app/l10n/l10n.dart';

import '../support/fake_booking_server.dart';

/// The fixture ride's start, as the fixture JSON has it.
final _start = DateTime.utc(2030, 10, 26, 5);

/// The details view model for one ride served by [server], with the list
/// seeded (no load request) and the clock at [now].
RideDetailsViewModel _vm(
  FakeBookingServer server, {
  DateTime Function()? now,
  MyBookingsViewModel? bookings,
  UpiCheckout? checkout,
}) {
  final repo = server.repository();
  return RideDetailsViewModel(
    repository: repo,
    bookings:
        bookings ??
        MyBookingsViewModel(
          repository: repo,
          initialBookings: [
            for (final json in server.bookings) MyBooking.tryParse(json)!,
          ],
        ),
    bookingId: 'b1',
    now: now,
    checkout: checkout,
    paySyncEvery: Duration.zero,
  );
}

/// A rides list whose reloads never see the latest — as when the list
/// request fails or races — so only the server's refusal tells the fee.
class _LaggingBookings extends MyBookingsViewModel {
  _LaggingBookings(FakeBookingServer server)
    : super(
        repository: server.repository(),
        initialBookings: [MyBooking.tryParse(bookingJson(otp: '4821'))!],
      );

  @override
  Future<void> load() async {}
}

/// A payment page that closes with [outcome] and remembers what it opened.
class _FakeCheckout implements UpiCheckout {
  _FakeCheckout(this.outcome, {this.onOpen});

  final CheckoutOutcome outcome;
  final List<PaymentCheckout> opened = [];

  /// Runs while the page is "open", before it closes with [outcome].
  final void Function()? onOpen;

  @override
  Future<CheckoutOutcome> open(
    PaymentCheckout checkout, {
    required String flowId,
  }) async {
    opened.add(checkout);
    onOpen?.call();
    return outcome;
  }
}

void main() {
  group('cancel', () {
    test('cancels with the reason and moves the ride to Completed', () async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      final repo = server.repository();
      final bookings = MyBookingsViewModel(repository: repo);
      await bookings.load();
      final vm = _vm(server, bookings: bookings);
      check(vm.booking!.canCancel).isTrue();

      check(vm.cancelFeePaise).equals(0);
      final cancelling = vm.cancel(reason: 'Plans changed', acceptFeePaise: 0);
      check(vm.isCancelling).isTrue();
      check(await cancelling).equals(CancelOutcome.cancelled);

      check(vm.isCancelling).isFalse();
      check(vm.booking!.status).equals(BookingStatus.cancelled);
      check(
        vm.booking!.cancellationSummaryIn(L10n.current),
      ).equals('Cancelled by you · Plans changed');
      check(bookings.active).isEmpty();
      check(bookings.past.single.id).equals('b1');
      // Free before the driver reaches the pickup: nothing to pay.
      check(vm.booking!.hasCancellationFee).isFalse();
      check(vm.booking!.canPay).isFalse();
      check(
        jsonDecode(server.requests[1].body) as Map,
      ).deepEquals({'reason': 'Plans changed', 'acceptFeePaise': 0});
      // The list is re-read after the cancel.
      await bookings.load();
      check(server.requests.map((r) => '${r.method} ${r.url.path}')).deepEquals(
        ['GET /me/bookings', 'POST /me/bookings/b1/cancel', 'GET /me/bookings'],
      );
    });

    test(
      'a ride that already started explains why it cannot be cancelled',
      () async {
        final server = FakeBookingServer([bookingJson()])
          ..actionError = (409, 'booking_state');
        final vm = _vm(server);

        check(
          await vm.cancel(reason: 'Plans changed', acceptFeePaise: 0),
        ).equals(CancelOutcome.failed);
        check(vm.cancelError).isNotNull().contains('already started');
        check(vm.booking!.status).equals(BookingStatus.accepted);
      },
    );

    test('a ride on its trip offers no cancel and sends nothing', () async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      final vm = _vm(server);
      check(vm.booking!.canCancel).isFalse();
      check(vm.cancelFeePaise).equals(0);
      check(await vm.cancel(acceptFeePaise: 0)).equals(CancelOutcome.failed);
      check(server.requests.where((r) => r.method == 'POST')).isEmpty();
    });

    Map<String, dynamic> atPickup() =>
        bookingJson(status: 'arrived', otp: '4821', cancellationFeePaise: 5000);

    test('at the pickup, cancelling costs the fee the server names, and '
        'the ride is then due for it', () async {
      final server = FakeBookingServer([atPickup()]);
      final vm = _vm(server, checkout: _FakeCheckout(CheckoutOutcome.success));
      check(vm.cancelFeePaise).equals(5000);

      check(
        await vm.cancel(reason: 'Plans changed', acceptFeePaise: 5000),
      ).equals(CancelOutcome.cancelled);

      final post = server.requests.firstWhere((r) => r.method == 'POST');
      check(
        jsonDecode(post.body) as Map,
      ).deepEquals({'reason': 'Plans changed', 'acceptFeePaise': 5000});
      final b = vm.booking!;
      check(b.status).equals(BookingStatus.cancelled);
      check(b.hasCancellationFee).isTrue();
      check(b.chargePaise).equals(5000);
      check(b.paymentStatus).equals(RidePaymentStatus.due);
      check(vm.canPay).isTrue();
      check(vm.cancelFeePaise).equals(0);
    });

    test('a driver who reaches the pickup after the sheet opened gets the '
        'fee shown before anything is cancelled', () async {
      final server = FakeBookingServer([bookingJson(otp: '4821')]);
      final repo = server.repository();
      final bookings = MyBookingsViewModel(repository: repo);
      await bookings.load();
      final vm = _vm(server, bookings: bookings);
      // The sheet opened while the driver was on the way: free.
      final shown = vm.cancelFeePaise;
      check(shown).equals(0);
      // Then the driver arrives.
      server.bookings[0] = atPickup();

      check(
        await vm.cancel(reason: 'Plans changed', acceptFeePaise: shown),
      ).equals(CancelOutcome.feeChanged);

      // Nothing cancelled; the list shows the driver at the pickup and the
      // fee to confirm.
      check(server.bookings[0]['status']).equals('arrived');
      check(vm.booking!.status).equals(BookingStatus.arrived);
      check(vm.cancelFeePaise).equals(5000);
      check(vm.cancelError).isNull();
      check(vm.isCancelling).isFalse();
      check(server.requests.map((r) => '${r.method} ${r.url.path}')).deepEquals(
        ['GET /me/bookings', 'POST /me/bookings/b1/cancel', 'GET /me/bookings'],
      );

      // Confirming again with the fee shown cancels.
      check(
        await vm.cancel(reason: 'Plans changed', acceptFeePaise: 5000),
      ).equals(CancelOutcome.cancelled);
      check(vm.booking!.cancellationFeePaise).equals(5000);
    });

    test('the fee from the refusal counts even when the list lags', () async {
      // The list still says "on the way"; only the server's refusal names
      // the fee.
      final server = FakeBookingServer([atPickup()]);
      final vm = RideDetailsViewModel(
        repository: server.repository(),
        bookings: _LaggingBookings(server),
        bookingId: 'b1',
      );
      check(vm.cancelFeePaise).equals(0);

      check(
        await vm.cancel(acceptFeePaise: 0),
      ).equals(CancelOutcome.feeChanged);
      check(vm.booking!.status).equals(BookingStatus.accepted);
      check(vm.cancelFeePaise).equals(5000);
    });

    test('a fee refusal that names no fee is not offered free again', () async {
      final server = FakeBookingServer([bookingJson()])
        ..actionError = (409, 'cancellation_fee');
      final vm = _vm(server);

      check(
        await vm.cancel(reason: 'Plans changed', acceptFeePaise: 0),
      ).equals(CancelOutcome.failed);
      check(vm.cancelError).isNotNull().contains('has a fee');
    });
  });

  group('ending the trip early', () {
    test(
      'ends an in-progress trip and leaves it due for the time used',
      () async {
        final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
        final vm = _vm(
          server,
          checkout: _FakeCheckout(CheckoutOutcome.success),
        );
        check(vm.canEndTrip).isTrue();

        final ending = vm.endTrip();
        check(vm.isEndingTrip).isTrue();
        check(await ending).isTrue();

        check(vm.isEndingTrip).isFalse();
        final post = server.requests.firstWhere((r) => r.method == 'POST');
        check(post.url.path).equals('/me/bookings/b1/end');
        final b = vm.booking!;
        check(b.status).equals(BookingStatus.completed);
        check(b.endedEarly).isTrue();
        check(b.farePaise).equals(24000);
        check(b.bookedFarePaise).equals(64000);
        check(b.paymentStatus).equals(RidePaymentStatus.due);
        check(vm.canEndTrip).isFalse();
        check(vm.canPay).isTrue();
        check(rideTimeline(b).last.label).equals('Ended early');
      },
    );

    test('a trip that already ended says so and refreshes', () async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      final repo = server.repository();
      final bookings = MyBookingsViewModel(repository: repo);
      await bookings.load();
      final vm = _vm(server, bookings: bookings);
      // The driver ended it a moment ago.
      server.bookings[0] = bookingJson(status: 'completed');

      check(await vm.endTrip()).isFalse();
      check(vm.endTripError).equals("This trip isn't in progress any more.");
      await bookings.load();
      check(vm.booking!.status).equals(BookingStatus.completed);
      check(vm.canEndTrip).isFalse();
    });

    test('says when the trip is past its booked time, by the clock', () {
      var now = DateTime.utc(2030, 10, 26, 8);
      // Booked 3 h from 05:00, plus the 15-minute grace.
      final server = FakeBookingServer([
        bookingJson(status: 'in_progress', startedAt: '2030-10-26T05:00:00Z'),
      ]);
      final vm = _vm(server, now: () => now);
      check(vm.isPastBookedTime).isFalse();
      now = DateTime.utc(2030, 10, 26, 8, 16);
      check(vm.isPastBookedTime).isTrue();
    });

    test('only a trip in progress can be ended', () async {
      for (final status in ['accepted', 'arrived', 'completed', 'cancelled']) {
        final server = FakeBookingServer([bookingJson(status: status)]);
        final vm = _vm(server);
        check(because: status, vm.canEndTrip).isFalse();
        check(because: status, await vm.endTrip()).isFalse();
        check(because: status, server.requests).isEmpty();
      }
    });
  });

  group('paying', () {
    Map<String, dynamic> due() =>
        bookingJson(status: 'completed', paymentStatus: 'due');

    test('opens the UPI page, then shows the ride paid once the server '
        'confirms', () async {
      // The first check is the one made on opening the ride.
      final server = FakeBookingServer([due()])..paidAfterSyncs = 3;
      final checkout = _FakeCheckout(CheckoutOutcome.success);
      final vm = _vm(server, checkout: checkout);
      check(vm.canPay).isTrue();

      check(await vm.pay()).isTrue();

      check(checkout.opened.single.token).equals('order-token');
      check(checkout.opened.single.amountPaise).equals(64000);
      check(vm.booking!.paymentStatus).equals(RidePaymentStatus.paid);
      check(vm.payError).isNull();
      check(vm.canPay).isFalse();
      // Then the list is re-read: a payment can clear other rides too.
      check(
        server.requests.map((r) => '${r.method} ${r.url.path}'),
      ).deepEquals([
        'POST /me/bookings/b1/payment/sync',
        'POST /me/bookings/b1/payment',
        'POST /me/bookings/b1/payment/sync',
        'POST /me/bookings/b1/payment/sync',
        'GET /me/bookings',
      ]);
    });

    test('a page closed early says so and leaves the ride due', () async {
      final server = FakeBookingServer([due()]);
      final vm = _vm(
        server,
        checkout: _FakeCheckout(CheckoutOutcome.interrupted),
      );

      check(await vm.pay()).isFalse();
      check(vm.payError).equals('Payment cancelled.');
      check(vm.booking!.paymentStatus).equals(RidePaymentStatus.due);
      // Checked on opening, and once after, in case it went through anyway.
      check(
        server.requests.where((r) => r.url.path.endsWith('/sync')),
      ).length.equals(2);
      // Nothing went through, so paying again is fine.
      check(vm.canPay).isTrue();
    });

    test('opening a due ride finds a payment the app never heard back '
        'about', () async {
      // Android killed the app behind the UPI app; the money went through.
      final server = FakeBookingServer([due()])..paidAfterSyncs = 1;
      final checkout = _FakeCheckout(CheckoutOutcome.success);
      final vm = _vm(server, checkout: checkout);

      // Tapped before the open check answers: no second order.
      check(await vm.pay()).isTrue();

      check(checkout.opened).isEmpty();
      check(vm.booking!.paymentStatus).equals(RidePaymentStatus.paid);
      check(
        server.requests.where((r) => r.url.path.endsWith('/payment')),
      ).isEmpty();
    });

    test('a payment the bank is slow to confirm keeps Pay off, even on '
        'reopening, and keeps being checked until it lands', () {
      fakeAsync((async) {
        // Open check, five quick checks, then the slow ones: at +5 s, +15 s.
        final server = FakeBookingServer([due()])..paidAfterSyncs = 8;
        final repo = server.repository();
        final bookings = MyBookingsViewModel(
          repository: repo,
          initialBookings: [MyBooking.tryParse(server.bookings.single)!],
        );
        RideDetailsViewModel open() => RideDetailsViewModel(
          repository: repo,
          bookings: bookings,
          bookingId: 'b1',
          checkout: _FakeCheckout(CheckoutOutcome.success),
          paySyncEvery: Duration.zero,
        );
        final vm = open();
        bool? paid;
        vm.pay().then((v) => paid = v);
        async.elapse(const Duration(milliseconds: 1));

        check(paid).equals(false);
        check(vm.canPay).isFalse();
        check(vm.payError).isNotNull().startsWith("We're still confirming");

        // Leaving and coming back doesn't turn Pay back on.
        vm.dispose();
        final reopened = open();
        async.elapse(const Duration(milliseconds: 1));
        check(reopened.canPay).isFalse();
        check(reopened.payError).isNotNull().startsWith("We're still");
        final syncsBefore = server.requests.length;

        async.elapse(const Duration(seconds: 5));
        check(server.requests.length).equals(syncsBefore + 1);
        check(reopened.booking!.paymentStatus).equals(RidePaymentStatus.due);

        async.elapse(const Duration(seconds: 10));
        check(reopened.booking!.paymentStatus).equals(RidePaymentStatus.paid);
        check(bookings.isConfirmingPayment('b1')).isFalse();
        check(reopened.payError).isNull();
        check(reopened.canPay).isFalse();

        // The list was re-read once it landed, and nothing is left running.
        check(server.requests.last.url.path).equals('/me/bookings');
        async.elapse(const Duration(minutes: 15));
        check(server.requests.length).equals(syncsBefore + 3);
        reopened.dispose();
      });
    });

    test('after the limit, Pay comes back', () {
      fakeAsync((async) {
        final server = FakeBookingServer([due()]);
        final bookings = MyBookingsViewModel(
          repository: server.repository(),
          initialBookings: [MyBooking.tryParse(server.bookings.single)!],
        );
        bookings.confirmPayment(
          'b1',
          first: const Duration(seconds: 1),
          longest: const Duration(seconds: 4),
          giveUpAfter: const Duration(seconds: 10),
        );
        check(bookings.isConfirmingPayment('b1')).isTrue();

        // 1 + 2 + 4 + 4 s: four checks, then it stops.
        async.elapse(const Duration(seconds: 30));

        check(server.requests).length.equals(4);
        check(bookings.isConfirmingPayment('b1')).isFalse();
      });
    });

    test('a ride paid from an earlier attempt just shows as paid', () async {
      final server = FakeBookingServer([due()])
        ..paymentError = (409, 'already_paid')
        ..paidAfterSyncs = 1;
      final checkout = _FakeCheckout(CheckoutOutcome.success);
      final vm = _vm(server, checkout: checkout);

      check(await vm.pay()).isTrue();
      check(checkout.opened).isEmpty();
      check(vm.booking!.paymentStatus).equals(RidePaymentStatus.paid);
    });

    test(
      'leaving while the order is being made opens no payment page',
      () async {
        final server = FakeBookingServer([due()]);
        final checkout = _FakeCheckout(CheckoutOutcome.success);
        final vm = _vm(server, checkout: checkout);

        final paying = vm.pay();
        // Back out of the screen before the server answers with the order.
        vm.dispose();

        check(await paying).isFalse();
        check(checkout.opened).isEmpty();
      },
    );

    test(
      'leaving as the UPI page closes still gets the payment checked',
      () async {
        final server = FakeBookingServer([due()])..paidAfterSyncs = 2;
        final repo = server.repository();
        final bookings = MyBookingsViewModel(
          repository: repo,
          initialBookings: [MyBooking.tryParse(server.bookings.single)!],
        );
        late final RideDetailsViewModel vm;
        // The customer backs out of the ride screen right as PhonePe returns.
        final checkout = _FakeCheckout(
          CheckoutOutcome.success,
          onOpen: () => vm.dispose(),
        );
        vm = RideDetailsViewModel(
          repository: repo,
          bookings: bookings,
          bookingId: 'b1',
          checkout: checkout,
          paySyncEvery: Duration.zero,
        );

        await vm.pay();

        // The list the Activity tab shows has the ride paid, so it doesn't
        // offer to take the money again.
        check(
          bookings.byId('b1')!.paymentStatus,
        ).equals(RidePaymentStatus.paid);
      },
    );

    test(
      'a payment still going through from an earlier attempt says so',
      () async {
        final server = FakeBookingServer([due()])
          ..paymentError = (409, 'payment_underway');
        final checkout = _FakeCheckout(CheckoutOutcome.success);
        final vm = _vm(server, checkout: checkout);

        check(await vm.pay()).isFalse();
        check(vm.payError).equals(
          'Your last payment is still going through. Check your UPI app, or '
          'try again in a few minutes.',
        );
      },
    );

    test('payments not set up on the server', () async {
      final server = FakeBookingServer([due()])
        ..paymentError = (503, 'payments_not_configured');
      final vm = _vm(server, checkout: _FakeCheckout(CheckoutOutcome.success));

      check(await vm.pay()).isFalse();
      check(vm.payError).equals("Paying in the app isn't available yet.");
    });

    test(
      'a cancellation fee pays through the same checkout, for the fee',
      () async {
        final server = FakeBookingServer([
          bookingJson(
            status: 'cancelled',
            cancellationFeePaise: 5000,
            paymentStatus: 'due',
          ),
        ])..paidAfterSyncs = 2;
        final checkout = _FakeCheckout(CheckoutOutcome.success);
        final vm = _vm(server, checkout: checkout);
        check(vm.canPay).isTrue();

        check(await vm.pay()).isTrue();

        check(checkout.opened.single.amountPaise).equals(5000);
        check(vm.booking!.paymentStatus).equals(RidePaymentStatus.paid);
        check(
          server.requests.map((r) => '${r.method} ${r.url.path}'),
        ).deepEquals([
          'POST /me/bookings/b1/payment/sync',
          'POST /me/bookings/b1/payment',
          'POST /me/bookings/b1/payment/sync',
          'GET /me/bookings',
        ]);
      },
    );

    group('with dues carried from other rides', () {
      /// A trip due for ₹640 that also collects a ₹50 fee still unpaid on
      /// another ride, which in turn would collect the trip's ₹640, and an
      /// upcoming ride that will collect both.
      List<Map<String, dynamic>> owing() => [
        bookingJson(
          status: 'completed',
          paymentStatus: 'due',
          carriedPaise: 5000,
        ),
        bookingJson(
          id: 'fee',
          status: 'cancelled',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
          carriedPaise: 64000,
          scheduledAt: '2030-10-20T05:00:00Z',
        ),
        bookingJson(
          id: 'next',
          status: 'accepted',
          carriedPaise: 69000,
          scheduledAt: '2030-11-01T05:00:00Z',
        ),
      ];

      test('one payment for the total, and every ride it covered then '
          'shows as paid', () async {
        final server = FakeBookingServer(owing())..paidAfterSyncs = 2;
        final repo = server.repository();
        final bookings = MyBookingsViewModel(repository: repo);
        await bookings.load();
        final checkout = _FakeCheckout(CheckoutOutcome.success);
        final vm = _vm(server, bookings: bookings, checkout: checkout);
        check(vm.booking!.totalDuePaise).equals(69000);
        check(vm.carriedDues).equals((paise: 5000, oneRide: true));

        check(await vm.pay()).isTrue();

        check(checkout.opened.single.amountPaise).equals(69000);
        // The list was re-read after the payment landed.
        check(
          server.requests.map((r) => '${r.method} ${r.url.path}'),
        ).deepEquals([
          'GET /me/bookings',
          'POST /me/bookings/b1/payment/sync',
          'POST /me/bookings/b1/payment',
          'POST /me/bookings/b1/payment/sync',
          'GET /me/bookings',
        ]);
        check(
          bookings.byId('fee')!.paymentStatus,
        ).equals(RidePaymentStatus.paid);
        check(bookings.byId('next')!.carriedPaise).equals(0);
        check(bookings.owed).isNull();
        check(vm.carriedDues).isNull();
      });

      test('a payment being confirmed for one ride keeps Pay off on the '
          'others it covers', () {
        fakeAsync((async) {
          final server = FakeBookingServer(owing());
          final repo = server.repository();
          final bookings = MyBookingsViewModel(
            repository: repo,
            initialBookings: [
              for (final json in server.bookings) MyBooking.tryParse(json)!,
            ],
          );
          final fee = RideDetailsViewModel(
            repository: repo,
            bookings: bookings,
            bookingId: 'fee',
            checkout: _FakeCheckout(CheckoutOutcome.success),
            paySyncEvery: Duration.zero,
          );
          async.elapse(const Duration(milliseconds: 1));
          check(fee.canPay).isTrue();

          // The trip's payment went through in the UPI app; the bank is slow.
          bookings.confirmPayment('b1');
          async.elapse(const Duration(milliseconds: 1));
          check(fee.canPay).isFalse();
          check(fee.payError).isNotNull().startsWith("We're still");

          // It lands; the list is re-read and the fee shows as paid.
          server.paidAfterSyncs = 1;
          async.elapse(const Duration(seconds: 5));
          check(bookings.isConfirmingPayment('fee')).isFalse();
          check(fee.booking!.paymentStatus).equals(RidePaymentStatus.paid);
          check(fee.canPay).isFalse();
          fee.dispose();
        });
      });

      test('the amount carried is named as one ride only when the list '
          'shows it', () {
        final server = FakeBookingServer(owing());
        final bookings = MyBookingsViewModel(
          repository: server.repository(),
          initialBookings: [
            for (final json in server.bookings) MyBooking.tryParse(json)!,
          ],
        );
        MyBooking ride(String id) => bookings.byId(id)!;
        check(
          bookings.carriedWith(ride('b1')),
        ).equals((paise: 5000, oneRide: true));
        check(
          bookings.carriedWith(ride('fee')),
        ).equals((paise: 64000, oneRide: true));
        // Two rides owe what the upcoming one carries.
        check(
          bookings.carriedWith(ride('next')),
        ).equals((paise: 69000, oneRide: false));
        check(bookings.owed).equals((paise: 69000, oneRide: false));

        // A carried amount the list can't account for: "other rides".
        final unknown = MyBookingsViewModel(
          repository: server.repository(),
          initialBookings: [
            MyBooking.tryParse(
              bookingJson(status: 'accepted', carriedPaise: 5000),
            )!,
          ],
        );
        check(
          unknown.carriedWith(unknown.byId('b1')!),
        ).equals((paise: 5000, oneRide: false));
        check(unknown.owed).equals((paise: 5000, oneRide: false));
      });

      test('what a new booking will collect, from what the list knows', () {
        MyBookingsViewModel list(List<Map<String, dynamic>> rides) =>
            MyBookingsViewModel(
              repository: FakeBookingServer(rides).repository(),
              initialBookings: [
                for (final json in rides) MyBooking.tryParse(json)!,
              ],
            );
        check(list([]).owed).isNull();
        check(list([bookingJson(status: 'completed')]).owed).isNull();
        check(
          list([
            bookingJson(
              status: 'cancelled',
              cancellationFeePaise: 5000,
              paymentStatus: 'due',
            ),
          ]).owed,
        ).equals((paise: 5000, oneRide: true));
        // A server that doesn't carry dues: the due rides added up.
        check(
          list([
            bookingJson(status: 'completed', paymentStatus: 'due'),
            bookingJson(
              id: 'fee',
              status: 'cancelled',
              cancellationFeePaise: 5000,
              paymentStatus: 'due',
            ),
          ]).owed,
        ).equals((paise: 69000, oneRide: false));
      });
    });

    test('a ride cancelled for free has nothing to pay', () async {
      final server = FakeBookingServer([bookingJson(status: 'cancelled')]);
      final vm = _vm(server, checkout: _FakeCheckout(CheckoutOutcome.success));
      check(vm.canPay).isFalse();
      check(await vm.pay()).isFalse();
      check(server.requests).isEmpty();
    });

    test('nothing to pay before the trip is done', () async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      final vm = _vm(server, checkout: _FakeCheckout(CheckoutOutcome.success));
      check(vm.canPay).isFalse();
      check(await vm.pay()).isFalse();
      check(server.requests).isEmpty();
    });
  });

  group('rating', () {
    test('needs stars, then sends them with the note', () async {
      final server = FakeBookingServer([bookingJson(status: 'completed')]);
      final vm = _vm(server);
      check(vm.canSubmitRating).isFalse();

      vm
        ..setRatingStars(4)
        ..setRatingNote('Careful driver');
      check(vm.canSubmitRating).isTrue();
      check(await vm.submitRating()).isTrue();

      final post = server.requests.firstWhere((r) => r.method == 'POST');
      check(post.url.path).equals('/me/bookings/b1/rating');
      check(
        jsonDecode(post.body) as Map,
      ).deepEquals({'stars': 4, 'note': 'Careful driver'});
      check(vm.booking!.myRating!.stars).equals(4);
      check(vm.booking!.canRate).isFalse();
      check(vm.canSubmitRating).isFalse();
    });

    test('a ride rated elsewhere says so', () async {
      final server = FakeBookingServer([bookingJson(status: 'completed')])
        ..actionError = (409, 'booking_state');
      final vm = _vm(server)..setRatingStars(5);

      check(await vm.submitRating()).isFalse();
      check(vm.ratingError).equals('This ride has already been rated.');
    });
  });

  group('live tracking', () {
    test('opens an hour before an accepted ride starts', () {
      final server = FakeBookingServer([bookingJson()]);
      var now = _start.subtract(const Duration(minutes: 61));
      final vm = _vm(server, now: () => now);
      check(vm.isTracking).isFalse();
      now = _start.subtract(const Duration(minutes: 59));
      check(vm.isTracking).isTrue();
    });

    test('words how far the driver is and how fresh the fix is', () {
      final now = _start.subtract(const Duration(minutes: 30));
      final server = FakeBookingServer([bookingJson()])
        ..location = {
          // ~2.3 km north of the pickup.
          'lat': 28.6522,
          'lng': 77.2167,
          'updatedAt': now
              .subtract(const Duration(seconds: 10))
              .toIso8601String(),
        };
      fakeAsync((async) {
        final vm = _vm(server, now: () => now);
        check(vm.trackingLine).startsWith('Finding');
        vm.startTracking();
        async.flushMicrotasks();
        check(vm.trackingLine).equals('Ravi is 2.3 km away · updated 10 s ago');

        server.location = null;
        async.elapse(const Duration(seconds: 5));
        check(vm.trackingLine).equals("Waiting for your driver's location");
        vm.dispose();
      });
    });

    test('polls every 5 s only while visible, and stops on not_tracking', () {
      final server = FakeBookingServer([bookingJson(status: 'arrived')]);
      fakeAsync((async) {
        final vm = _vm(server);
        check(vm.isPolling).isFalse();

        vm.startTracking();
        async.flushMicrotasks();
        check(server.locationRequests).equals(1);
        async.elapse(const Duration(seconds: 10));
        check(server.locationRequests).equals(3);

        vm.stopTracking();
        check(vm.isPolling).isFalse();
        async.elapse(const Duration(seconds: 30));
        check(server.locationRequests).equals(3);

        vm.startTracking();
        async.flushMicrotasks();
        check(server.locationRequests).equals(4);
        server.locationError = (409, 'not_tracking');
        async.elapse(const Duration(seconds: 5));
        check(server.locationRequests).equals(5);
        check(vm.isPolling).isFalse();
        check(vm.isTracking).isFalse();
        async.elapse(const Duration(seconds: 30));
        check(server.locationRequests).equals(5);
        vm.dispose();
      });
    });

    test('waits for the window before asking, without reopening', () {
      final server = FakeBookingServer([bookingJson()]);
      var now = _start.subtract(const Duration(minutes: 62));
      fakeAsync((async) {
        final vm = _vm(server, now: () => now)..startTracking();
        async.elapse(const Duration(seconds: 10));
        check(server.locationRequests).equals(0);

        now = _start.subtract(const Duration(minutes: 59));
        async.elapse(const Duration(seconds: 5));
        check(server.locationRequests).equals(1);
        vm.dispose();
      });
    });

    test('never polls a ride with no driver', () {
      final server = FakeBookingServer([
        bookingJson(status: 'requested', withDriver: false),
      ]);
      fakeAsync((async) {
        final vm = _vm(server)..startTracking();
        check(vm.isPolling).isFalse();
        async.elapse(const Duration(seconds: 30));
        check(server.locationRequests).equals(0);
        vm.dispose();
      });
    });
  });

  group('rating prompt', () {
    final completedAt = DateTime.utc(2030, 10, 26, 7, 40);

    MyBookingsViewModel prompts(
      FakeBookingServer server, {
      Duration since = const Duration(hours: 2),
    }) => MyBookingsViewModel(
      repository: server.repository(),
      now: () => completedAt.add(since),
    );

    test(
      'on load, asks about the latest ride if it ended within 24 h',
      () async {
        final server = FakeBookingServer([
          bookingJson(status: 'completed', completedAt: '2030-10-26T07:40:00Z'),
        ]);
        final vm = prompts(server);
        await vm.load();
        check(vm.ratingPrompt?.id).equals('b1');

        // Asked once — whether rated or waved away, never again this session.
        vm.markRatingAsked('b1');
        check(vm.ratingPrompt).isNull();
        await vm.load();
        check(vm.ratingPrompt).isNull();
      },
    );

    test('leaves older, rated or not-latest rides alone', () async {
      final old = FakeBookingServer([
        bookingJson(status: 'completed', completedAt: '2030-10-26T07:40:00Z'),
      ]);
      final stale = prompts(old, since: const Duration(hours: 25));
      await stale.load();
      check(stale.ratingPrompt).isNull();

      final rated = FakeBookingServer([
        bookingJson(
          status: 'completed',
          completedAt: '2030-10-26T07:40:00Z',
          myRating: {'stars': 5},
        ),
        bookingJson(
          id: 'older',
          status: 'completed',
          completedAt: '2030-10-26T06:00:00Z',
        ),
      ]);
      final vm = prompts(rated);
      await vm.load();
      check(vm.ratingPrompt).isNull();
    });

    test('asks about a ride that finishes while the app is open', () async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      // Long after: only the "finished while open" rule can fire.
      final vm = prompts(server, since: const Duration(days: 3));
      await vm.load();
      check(vm.ratingPrompt).isNull();

      server.bookings[0] = bookingJson(status: 'completed');
      await vm.load();
      check(vm.ratingPrompt?.id).equals('b1');
    });
  });
}
