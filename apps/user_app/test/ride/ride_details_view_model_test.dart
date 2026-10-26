import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/upi_checkout.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/payment_checkout.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/features/ride/view_model/ride_details_view_model.dart';

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

/// A payment page that closes with [outcome] and remembers what it opened.
class _FakeCheckout implements UpiCheckout {
  _FakeCheckout(this.outcome);

  final CheckoutOutcome outcome;
  final List<PaymentCheckout> opened = [];

  @override
  Future<CheckoutOutcome> open(
    PaymentCheckout checkout, {
    required String flowId,
  }) async {
    opened.add(checkout);
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

      final cancelling = vm.cancel(reason: 'Plans changed');
      check(vm.isCancelling).isTrue();
      check(await cancelling).isTrue();

      check(vm.isCancelling).isFalse();
      check(vm.booking!.status).equals(BookingStatus.cancelled);
      check(
        vm.booking!.cancellationSummary,
      ).equals('Cancelled by you · Plans changed');
      check(bookings.active).isEmpty();
      check(bookings.past.single.id).equals('b1');
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

        check(await vm.cancel(reason: 'Plans changed')).isFalse();
        check(vm.cancelError).isNotNull().contains('already started');
        check(vm.booking!.status).equals(BookingStatus.accepted);
      },
    );

    test('a ride on its trip offers no cancel and sends nothing', () async {
      final server = FakeBookingServer([bookingJson(status: 'in_progress')]);
      final vm = _vm(server);
      check(vm.booking!.canCancel).isFalse();
      check(await vm.cancel()).isFalse();
      check(server.requests.where((r) => r.method == 'POST')).isEmpty();
    });
  });

  group('paying', () {
    Map<String, dynamic> due() =>
        bookingJson(status: 'completed', paymentStatus: 'due');

    test('opens the UPI page, then shows the ride paid once the server '
        'confirms', () async {
      final server = FakeBookingServer([due()])..paidAfterSyncs = 2;
      final checkout = _FakeCheckout(CheckoutOutcome.success);
      final vm = _vm(server, checkout: checkout);
      check(vm.canPay).isTrue();

      check(await vm.pay()).isTrue();

      check(checkout.opened.single.token).equals('order-token');
      check(checkout.opened.single.amountPaise).equals(64000);
      check(vm.booking!.paymentStatus).equals(RidePaymentStatus.paid);
      check(vm.payError).isNull();
      check(vm.canPay).isFalse();
      check(
        server.requests.map((r) => '${r.method} ${r.url.path}'),
      ).deepEquals([
        'POST /me/bookings/b1/payment',
        'POST /me/bookings/b1/payment/sync',
        'POST /me/bookings/b1/payment/sync',
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
      // Checked once, in case it went through anyway.
      check(
        server.requests.where((r) => r.url.path.endsWith('/sync')),
      ).length.equals(1);
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

    test('payments not set up on the server', () async {
      final server = FakeBookingServer([due()])
        ..paymentError = (503, 'payments_not_configured');
      final vm = _vm(server, checkout: _FakeCheckout(CheckoutOutcome.success));

      check(await vm.pay()).isFalse();
      check(vm.payError).equals("Paying in the app isn't available yet.");
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
