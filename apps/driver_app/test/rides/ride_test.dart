import 'package:checks/checks.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('Ride.tryParse — cancellation', () {
    test('reads cancelledAt, cancelledBy and cancelReason', () {
      final parsed = Ride.tryParse(
        rideJson(
          status: 'cancelled',
          cancelledAt: '2026-10-25T08:00:00+05:30',
          cancelledBy: 'customer',
          cancelReason: 'Driver is not responding',
        ),
      )!;

      check(parsed.status).equals(RideStatus.cancelled);
      check(parsed.cancelledBy).equals('customer');
      check(parsed.cancelReason).equals('Driver is not responding');
      check(parsed.cancelledAt).isNotNull();
    });

    test('leaves cancellation fields null when absent', () {
      final parsed = Ride.tryParse(rideJson())!;
      check(parsed.cancelledAt).isNull();
      check(parsed.cancelledBy).isNull();
      check(parsed.cancelReason).isNull();
    });
  });

  group('Ride.tryParse — myRating', () {
    test('reads stars and note', () {
      final parsed = Ride.tryParse(
        rideJson(
          status: 'completed',
          myRating: {'stars': 4, 'note': 'Great customer'},
        ),
      )!;
      check(parsed.myRating!.stars).equals(4);
      check(parsed.myRating!.note).equals('Great customer');
    });

    test('is null when absent', () {
      final parsed = Ride.tryParse(rideJson(status: 'completed'))!;
      check(parsed.myRating).isNull();
    });

    test('RideRating.tryParse skips an unreadable stars field', () {
      check(RideRating.tryParse({'note': 'no stars'})).isNull();
      check(RideRating.tryParse('not a map')).isNull();
      check(RideRating.tryParse(null)).isNull();
    });
  });

  group('Ride.tryParse — customer rating', () {
    test('reads rating and ratingCount', () {
      final parsed = Ride.tryParse(
        rideJson(
          withCustomer: true,
          customerRating: 4.9,
          customerRatingCount: 3,
        ),
      )!;
      check(parsed.customer!.rating).equals(4.9);
      check(parsed.customer!.ratingCount).equals(3);
    });

    test('rating is null when the backend omits it (count 0)', () {
      final parsed = Ride.tryParse(rideJson(withCustomer: true))!;
      check(parsed.customer!.rating).isNull();
      check(parsed.customer!.ratingCount).equals(0);
    });
  });

  group('Earnings — rating', () {
    test('parses average and count', () {
      final e = Earnings.fromJson({
        'today': {'farePaise': 0, 'rides': 0},
        'rating': {'average': 4.8, 'count': 12},
      });
      check(e.rating!.average).equals(4.8);
      check(e.rating!.count).equals(12);
    });

    test('is null when the backend omits it', () {
      final e = Earnings.fromJson({
        'today': {'farePaise': 0, 'rides': 0},
      });
      check(e.rating).isNull();
    });
  });

  group('Ride.isTrackableAt', () {
    final scheduled = DateTime.parse('2026-10-26T09:00:00+05:30');

    test('false for a ride the driver hasn\'t taken', () {
      final requested = ride(
        status: 'requested',
        scheduledAt: scheduled.toIso8601String(),
      );
      check(requested.isTrackableAt(scheduled)).isFalse();
    });

    test('false more than 60 minutes before pickup', () {
      final accepted = ride(
        status: 'accepted',
        scheduledAt: scheduled.toIso8601String(),
      );
      check(
        accepted.isTrackableAt(scheduled.subtract(const Duration(minutes: 61))),
      ).isFalse();
    });

    test('true from exactly 60 minutes out, through pickup and the trip', () {
      final accepted = ride(
        status: 'accepted',
        scheduledAt: scheduled.toIso8601String(),
      );
      check(
        accepted.isTrackableAt(scheduled.subtract(const Duration(minutes: 60))),
      ).isTrue();
      check(accepted.isTrackableAt(scheduled)).isTrue();

      final inProgress = ride(
        status: 'in_progress',
        scheduledAt: scheduled.toIso8601String(),
      );
      check(
        inProgress.isTrackableAt(scheduled.add(const Duration(hours: 2))),
      ).isTrue();
    });

    test('false once completed or cancelled, regardless of time', () {
      final completed = ride(
        status: 'completed',
        scheduledAt: scheduled.toIso8601String(),
      );
      check(completed.isTrackableAt(scheduled)).isFalse();

      final cancelled = ride(
        status: 'cancelled',
        scheduledAt: scheduled.toIso8601String(),
      );
      check(cancelled.isTrackableAt(scheduled)).isFalse();
    });
  });

  group('payments', () {
    test('a paid ride carries its status, time and the driver\'s share', () {
      final parsed = Ride.tryParse({
        ...rideJson(status: 'completed'),
        'paymentStatus': 'paid',
        'paidAt': '2026-10-26T12:00:00+05:30',
        'sharePaise': 25500,
      })!;
      check(parsed.paymentStatus).equals(RidePaymentStatus.paid);
      check(parsed.paymentStatus.label).equals('Paid');
      check(parsed.paidAt).isNotNull();
      check(parsed.sharePaise).equals(25500);
    });

    test('older servers send no payment fields', () {
      final parsed = Ride.tryParse(rideJson(status: 'completed'))!;
      check(parsed.paymentStatus).equals(RidePaymentStatus.none);
      check(parsed.sharePaise).isNull();
    });

    test('earnings read the money summary, or zeros without one', () {
      final e = Earnings.fromJson({
        'payments': {
          'awaitingCustomerPaise': 30000,
          'awaitingCustomerRides': 1,
          'duePaise': 25500,
          'dueRides': 1,
          'paidOutPaise': 28900,
          'lastPayoutAt': '2026-10-26T17:14:53+05:30',
        },
      });
      check(e.payments.duePaise).equals(25500);
      check(e.payments.paidOutPaise).equals(28900);
      check(e.payments.lastPayoutAt).isNotNull();
      check(Earnings.fromJson({}).payments.duePaise).equals(0);
    });
  });
}
