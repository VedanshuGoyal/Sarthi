import 'package:checks/checks.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/view/ride_labels.dart';
import 'package:driver_app/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('Ride.tryParse — approximate requests', () {
    test('reads the approximate flag of an open request', () {
      final parsed = Ride.tryParse(rideJson(approximate: true))!;
      check(parsed.approximate).isTrue();
      check(parsed.pickup.address).equals('Saket, New Delhi');
      check(parsed.car!.registration).isEmpty();
    });

    test('is exact unless the backend says otherwise', () {
      check(Ride.tryParse(rideJson(status: 'accepted'))!.approximate).isFalse();
    });

    test('a merged update keeps the newer exactness', () {
      final request = Ride.tryParse(rideJson(approximate: true))!;
      final accepted = Ride.tryParse(
        rideJson(status: 'accepted', withCustomer: true),
      )!;
      check(request.mergedWith(accepted).approximate).isFalse();
    });
  });

  group('Ride — no-show', () {
    test('reads noShowAt and opens the no-show from then', () {
      final waiting = Ride.tryParse(
        rideJson(status: 'arrived', noShowAt: '2026-10-26T09:15:00+05:30'),
      )!;
      final at = DateTime.parse('2026-10-26T09:15:00+05:30');
      check(waiting.noShowAt).equals(at.toLocal());
      check(
        waiting.canCloseAsNoShowAt(at.subtract(const Duration(seconds: 1))),
      ).isFalse();
      check(waiting.canCloseAsNoShowAt(at)).isTrue();
      // Not at the pickup, or no time from the backend: never.
      check(
        Ride.tryParse(rideJson(status: 'accepted'))!.canCloseAsNoShowAt(at),
      ).isFalse();
    });

    test('names who ended a cancelled ride', () {
      String label(String? by) => Ride.tryParse(
        rideJson(status: 'cancelled', cancelledBy: by),
      )!.cancelLabelIn(L10n.current);
      check(label('customer')).equals('Cancelled by customer');
      check(label('no_show')).equals("Customer didn't come");
      check(label(null)).equals('Cancelled');
    });
  });

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

  group('Ride — booked time', () {
    Ride trip({
      String tripType = 'oneWay',
      String endsAt = '2026-10-26T12:00:00+05:30',
      int? hours,
      String status = 'in_progress',
      String? startedAt = '2026-10-26T09:10:00+05:30',
    }) => Ride.tryParse({
      ...rideJson(tripType: tripType, status: status),
      'endsAt': endsAt,
      'hours': hours,
      'startedAt': startedAt,
    })!;

    test('a round trip is booked for its hours', () {
      check(trip(tripType: 'roundTrip', hours: 3).bookedHours).equals(3);
      // The hours win over the span.
      check(
        trip(
          tripType: 'roundTrip',
          hours: 4,
          endsAt: '2026-10-26T10:00:00+05:30',
        ).bookedHours,
      ).equals(4);
      // No hours sent: the span, as for the other kinds.
      check(trip(tripType: 'roundTrip').bookedHours).equals(3);
    });

    test('other trips are booked for their span rounded up to whole hours, '
        'at least 1', () {
      // 09:00 → 12:00.
      check(trip().bookedHours).equals(3);
      check(trip(endsAt: '2026-10-26T10:45:00+05:30').bookedHours).equals(2);
      check(trip(endsAt: '2026-10-26T10:01:00+05:30').bookedHours).equals(2);
      check(
        trip(
          tripType: 'multiStop',
          endsAt: '2026-10-26T09:20:00+05:30',
        ).bookedHours,
      ).equals(1);
      check(trip(endsAt: '2026-10-26T09:00:00+05:30').bookedHours).equals(1);
      // A one-way trip's hours, if any, don't count.
      check(trip(hours: 5).bookedHours).equals(3);
    });

    test('a trip underway is past its booked time once its start plus the '
        'booked hours plus 15 minutes have gone by', () {
      final onTrip = trip(tripType: 'roundTrip', hours: 3);
      final from = DateTime.parse('2026-10-26T12:25:00+05:30');
      check(onTrip.overtimeFrom).equals(from.toLocal());
      check(
        onTrip.isPastBookedTimeAt(DateTime.parse('2026-10-26T12:10:00+05:30')),
      ).isFalse();
      check(onTrip.isPastBookedTimeAt(from)).isFalse();
      check(
        onTrip.isPastBookedTimeAt(from.add(const Duration(seconds: 1))),
      ).isTrue();

      // One way, 09:00 → 10:45 booked as 2 h: from 11:25.
      final oneWay = trip(endsAt: '2026-10-26T10:45:00+05:30');
      check(
        oneWay.isPastBookedTimeAt(DateTime.parse('2026-10-26T11:24:00+05:30')),
      ).isFalse();
      check(
        oneWay.isPastBookedTimeAt(DateTime.parse('2026-10-26T11:26:00+05:30')),
      ).isTrue();
    });

    test('only a trip underway, and started, can be past its booked time', () {
      final nextDay = DateTime.parse('2026-10-27T09:00:00+05:30');
      check(trip(status: 'completed').isPastBookedTimeAt(nextDay)).isFalse();
      check(trip(status: 'arrived').isPastBookedTimeAt(nextDay)).isFalse();
      final notStarted = trip(startedAt: null);
      check(notStarted.overtimeFrom).isNull();
      check(notStarted.isPastBookedTimeAt(nextDay)).isFalse();
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
      check(parsed.paymentStatus.labelIn(L10n.current)).equals('Paid');
      check(parsed.paidAt).isNotNull();
      check(parsed.sharePaise).equals(25500);
    });

    test('older servers send no payment fields', () {
      final parsed = Ride.tryParse(rideJson(status: 'completed'))!;
      check(parsed.paymentStatus).equals(RidePaymentStatus.none);
      check(parsed.sharePaise).isNull();
    });

    test('a ride the customer cancelled at the pickup carries its fee and '
        'payment', () {
      final parsed = Ride.tryParse(
        rideJson(
          status: 'cancelled',
          cancelledBy: 'customer',
          cancellationFeePaise: 5000,
          paymentStatus: 'paid',
          sharePaise: 4350,
        ),
      )!;
      check(parsed.cancellationFeePaise).equals(5000);
      check(parsed.hasCancellationFee).isTrue();
      check(parsed.paymentStatus).equals(RidePaymentStatus.paid);
      check(parsed.sharePaise).equals(4350);
      check(
        parsed.cancelLabelIn(L10n.current),
      ).equals('Customer cancelled at the pickup');
      check(parsed.endedEarly).isFalse();
    });

    test('a free cancellation has no fee and keeps its label', () {
      final parsed = Ride.tryParse(
        rideJson(status: 'cancelled', cancelledBy: 'customer'),
      )!;
      check(parsed.cancellationFeePaise).isNull();
      check(parsed.hasCancellationFee).isFalse();
      check(parsed.paymentStatus).equals(RidePaymentStatus.none);
      check(parsed.cancelLabelIn(L10n.current)).equals('Cancelled by customer');
      // A zero fee, or a fee on a ride that wasn't cancelled, is no fee.
      check(
        Ride.tryParse(
          rideJson(status: 'cancelled', cancellationFeePaise: 0),
        )!.hasCancellationFee,
      ).isFalse();
      check(
        Ride.tryParse(
          rideJson(status: 'arrived', cancellationFeePaise: 5000),
        )!.hasCancellationFee,
      ).isFalse();
    });

    test('a trip the customer ended early carries the booked fare', () {
      final parsed = Ride.tryParse(
        rideJson(
          status: 'completed',
          farePaise: 20000,
          bookedFarePaise: 34000,
          paymentStatus: 'due',
        ),
      )!;
      check(parsed.farePaise).equals(20000);
      check(parsed.bookedFarePaise).equals(34000);
      check(parsed.endedEarly).isTrue();
      check(parsed.paymentStatus).equals(RidePaymentStatus.due);
      check(Ride.tryParse(rideJson(status: 'completed'))!.endedEarly).isFalse();
    });

    test('a merged update keeps the fee and booked fare', () {
      final before = Ride.tryParse(
        rideJson(status: 'arrived', withCustomer: true),
      )!;
      final update = Ride.tryParse(
        rideJson(
          status: 'cancelled',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
        ),
      )!;
      final merged = before.mergedWith(update);
      check(merged.customer).isNotNull();
      check(merged.cancellationFeePaise).equals(5000);
      check(merged.paymentStatus).equals(RidePaymentStatus.due);

      final ended = before.mergedWith(
        Ride.tryParse(
          rideJson(
            status: 'completed',
            farePaise: 20000,
            bookedFarePaise: 34000,
          ),
        )!,
      );
      check(ended.bookedFarePaise).equals(34000);
      check(ended.farePaise).equals(20000);
    });

    test('a trip that ran past its booked time is charged more than booked, '
        'and is not an early end', () {
      final parsed = Ride.tryParse(
        rideJson(
          status: 'completed',
          farePaise: 51000,
          bookedFarePaise: 34000,
          paymentStatus: 'due',
        ),
      )!;
      check(parsed.farePaise).equals(51000);
      check(parsed.bookedFarePaise).equals(34000);
      check(parsed.ranOverTime).isTrue();
      check(parsed.endedEarly).isFalse();
    });

    test('a booked fare reads as an early end only when the charge is no '
        'more than it', () {
      Ride completed(int fare, int? booked) => Ride.tryParse(
        rideJson(status: 'completed', farePaise: fare, bookedFarePaise: booked),
      )!;
      // Charged exactly the booked fare: ended early (the existing copy).
      check(completed(34000, 34000).endedEarly).isTrue();
      check(completed(34000, 34000).ranOverTime).isFalse();
      check(completed(20000, 34000).ranOverTime).isFalse();
      // No booked fare: the trip ran its course.
      check(completed(34000, null).endedEarly).isFalse();
      check(completed(34000, null).ranOverTime).isFalse();
      // Not completed: neither, whatever the fares.
      final onTrip = Ride.tryParse(
        rideJson(
          status: 'in_progress',
          farePaise: 51000,
          bookedFarePaise: 34000,
        ),
      )!;
      check(onTrip.ranOverTime).isFalse();
      check(onTrip.endedEarly).isFalse();
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
