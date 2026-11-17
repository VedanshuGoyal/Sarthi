import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/view_model/ride_details_view_model.dart';

import '../support/fake_booking_server.dart';

void main() {
  test('parses every field the contract added', () {
    final b = MyBooking.tryParse(
      bookingJson(
        status: 'completed',
        completedAt: '2030-10-26T07:40:00Z',
        myRating: {'stars': 4, 'note': 'Careful driver'},
      ),
    )!;

    check(b.tripType).equals(TripType.multiStop);
    check(b.pickupPoint!.latitude).equals(28.6315);
    // The 0,0 placeholder is "no fix", not a point in the ocean.
    check(b.destinationPoint).isNull();
    check(b.destinationAddress).equals('Hauz Khas Village');
    check(b.stops.length).equals(2);
    check(b.stops.first.task).equals('Collect the prescription');
    check(b.stops.first.address).equals('Apollo Pharmacy');
    check(
      b.stops.first.departBy,
    ).equals(DateTime.utc(2030, 10, 26, 6).toLocal());
    check(b.estimatedMinutes).equals(150);
    check(b.duration).equals(const Duration(minutes: 150));
    check(b.carType).equals(CarType.sedan);
    check(b.transmission).equals(Transmission.manual);
    check(b.driverRating).equals(4.7);
    check(b.driverRatingCount).equals(12);
    check(b.driverFirstName).equals('Ravi');
    check(b.acceptedAt).equals(DateTime.utc(2030, 10, 25, 5).toLocal());
    check(b.completedAt).equals(DateTime.utc(2030, 10, 26, 7, 40).toLocal());
    check(b.myRating!.stars).equals(4);
    check(b.myRating!.note).equals('Careful driver');
    check(b.canRate).isFalse();
  });

  test('a cancelled booking says who cancelled and why', () {
    final b = MyBooking.tryParse(
      bookingJson(status: 'cancelled', cancelReason: 'Plans changed'),
    )!;
    check(b.cancelledBy).equals('customer');
    check(b.cancelledAt).isNotNull();
    check(b.cancellationSummary).equals('Cancelled by you · Plans changed');
    check(b.canCancel).isFalse();
  });

  test('a ride the driver closed as a no-show says so, with why', () {
    final b = MyBooking.tryParse(
      bookingJson(
        status: 'cancelled',
        cancelledBy: 'no_show',
        cancelReason: 'The driver waited at the pickup until 10:15 AM',
      ),
    )!;
    check(b.cancellationSummary).equals(
      'Closed as a no-show · The driver waited at the pickup until 10:15 AM',
    );
    final steps = rideTimeline(b);
    check(steps.last.label).equals('Closed as a no-show');
    check(steps.last.state).equals(MilestoneState.ended);
  });

  test("a driver's number the server has hidden is no number at all", () {
    final json = bookingJson(status: 'completed');
    (json['driver'] as Map<String, dynamic>)['phoneE164'] = '';
    final b = MyBooking.tryParse(json)!;
    check(b.driverName).equals('Ravi Kumar');
    check(b.driverPhone).isNull();
    check(
      MyBooking.tryParse(bookingJson())!.driverPhone,
    ).equals('+919800000001');
  });

  test('an old payload without the new fields still parses', () {
    final b = MyBooking.tryParse({
      'id': 'old',
      'tripType': 'roundTrip',
      'status': 'accepted',
      'scheduledAt': '2030-10-26T05:00:00Z',
      'farePaise': 44000,
      'pickup': {'address': 'Connaught Place'},
      'stopCount': 3,
      'driver': {'name': 'Ravi', 'phoneE164': '+91980'},
    })!;
    check(b.pickupPoint).isNull();
    check(b.stops).isEmpty();
    check(b.stopCount).equals(3);
    check(b.hours).isNull();
    check(b.carType).isNull();
    check(b.driverRating).isNull();
    check(b.driverRatingCount).equals(0);
    check(b.createdAt).isNull();
    check(b.myRating).isNull();
    check(b.canCancel).isTrue();
  });

  group('receipt', () {
    test('a paid ride carries how it was paid and its fare parts', () {
      final b = MyBooking.tryParse(
        bookingJson(
          status: 'completed',
          tripType: 'roundTrip',
          paymentStatus: 'paid',
          payment: {
            'mode': 'UPI_INTENT',
            'utr': '412345678901',
            'transactionId': 'T2411170001',
            'merchantOrderId': 'MOJUD_b1_m3k9',
            'paidAt': '2030-10-26T08:00:00Z',
          },
          fareBreakdown: {'basePaise': 54000, 'nightPaise': 10000},
        ),
      )!;
      final p = b.payment!;
      check(p.mode).equals('UPI_INTENT');
      check(p.modeLabel).equals('UPI');
      check(p.utr).equals('412345678901');
      check(p.reference).equals('412345678901');
      check(p.merchantOrderId).equals('MOJUD_b1_m3k9');
      check(p.paidAt).equals(DateTime.utc(2030, 10, 26, 8).toLocal());
      check(b.fareBreakdown!.basePaise).equals(54000);
      check(b.fareBreakdown!.nightPaise).equals(10000);
      check(b.fareBreakdown!.nightRupees).equals(100);
    });

    test('names every way a ride can be paid', () {
      String label(String mode) => RidePayment(mode: mode).modeLabel;
      check(label('UPI_QR')).equals('UPI');
      check(label('')).equals('UPI');
      check(label('CASH')).equals('Cash');
      check(label('WAIVED')).equals('Waived by MOJUD');
      check(label('NET_BANKING')).equals('Net Banking');
      check(label('CARD')).equals('Card');
    });

    test('the reference falls back to the transaction id', () {
      final p = RidePayment.tryParse({
        'mode': 'UPI_COLLECT',
        'transactionId': 'T1',
        'utr': '  ',
      })!;
      check(p.utr).isNull();
      check(p.reference).equals('T1');
      check(p.merchantOrderId).isNull();
    });

    test('a missing or garbled block reads as absent', () {
      final b = MyBooking.tryParse(bookingJson(paymentStatus: 'paid'))!;
      check(b.payment).isNull();
      check(b.fareBreakdown).isNull();

      check(RidePayment.tryParse('paid')).isNull();
      final odd = RidePayment.tryParse({'mode': 7, 'paidAt': 'yesterday'})!;
      check(odd.mode).equals('');
      check(odd.paidAt).isNull();

      check(FareBreakdown.tryParse({'basePaise': 'lots'})).isNull();
      check(FareBreakdown.tryParse({'nightPaise': 100})).isNull();
      check(
        FareBreakdown.tryParse({'basePaise': 100, 'nightPaise': -1}),
      ).isNull();
      check(FareBreakdown.tryParse({'basePaise': 24000})!.nightPaise).equals(0);
    });
  });

  group('cancellation charges', () {
    test('at the pickup, the booking says what cancelling now costs', () {
      final b = MyBooking.tryParse(
        bookingJson(status: 'arrived', cancellationFeePaise: 5000),
      )!;
      check(b.cancellationFeePaise).equals(5000);
      check(b.cancelFeeNowPaise).equals(5000);
      check(b.hasCancellationFee).isFalse();
      check(b.canPay).isFalse();
      check(b.bookedFarePaise).isNull();
    });

    test('before the pickup, and on old payloads, cancelling is free', () {
      for (final json in [
        bookingJson(),
        bookingJson(status: 'requested', withDriver: false),
        bookingJson(status: 'arrived'),
      ]) {
        final b = MyBooking.tryParse(json)!;
        check(b.cancellationFeePaise).equals(0);
        check(b.cancelFeeNowPaise).equals(0);
      }
    });

    test('a ride cancelled with a fee is due for the fee, then paid', () {
      final due = MyBooking.tryParse(
        bookingJson(
          status: 'cancelled',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
        ),
      )!;
      check(due.hasCancellationFee).isTrue();
      check(due.chargePaise).equals(5000);
      check(due.paymentStatus).equals(RidePaymentStatus.due);
      check(due.canPay).isTrue();
      // Nothing left to cancel, so nothing it would cost.
      check(due.cancelFeeNowPaise).equals(0);

      final paid = MyBooking.tryParse(
        bookingJson(
          status: 'cancelled',
          cancellationFeePaise: 5000,
          paymentStatus: 'paid',
        ),
      )!;
      check(paid.paymentStatus).equals(RidePaymentStatus.paid);
      check(paid.canPay).isFalse();
    });

    test('a ride cancelled for free has nothing to pay', () {
      final b = MyBooking.tryParse(bookingJson(status: 'cancelled'))!;
      check(b.hasCancellationFee).isFalse();
      check(b.chargePaise).equals(0);
      check(b.canPay).isFalse();
    });

    test('a trip ended early carries the booked fare beside the charge', () {
      final b = MyBooking.tryParse(
        bookingJson(
          status: 'completed',
          farePaise: 24000,
          bookedFarePaise: 64000,
          paymentStatus: 'due',
        ),
      )!;
      check(b.endedEarly).isTrue();
      check(b.farePaise).equals(24000);
      check(b.bookedFarePaise).equals(64000);
      check(b.chargePaise).equals(24000);
      check(b.canPay).isTrue();
      check(
        MyBooking.tryParse(bookingJson(status: 'completed'))!.endedEarly,
      ).isFalse();
    });

    test('garbled amounts read as absent', () {
      final b = MyBooking.tryParse({
        ...bookingJson(status: 'arrived'),
        'cancellationFeePaise': 'fifty',
        'bookedFarePaise': -1,
      })!;
      check(b.cancellationFeePaise).equals(0);
      check(b.bookedFarePaise).isNull();
    });

    test('only a trip in progress can be ended early', () {
      for (final status in BookingStatus.values) {
        final b = MyBooking.tryParse(bookingJson(status: status.wireName))!;
        check(
          because: status.name,
          b.canEndTrip,
        ).equals(status == BookingStatus.inProgress);
      }
    });
  });

  group('dues carried to the next payment', () {
    test('a due ride collects what other rides owe with its own charge', () {
      final b = MyBooking.tryParse(
        bookingJson(
          status: 'completed',
          paymentStatus: 'due',
          carriedPaise: 5000,
        ),
      )!;
      check(b.carriedPaise).equals(5000);
      check(b.chargePaise).equals(64000);
      check(b.totalDuePaise).equals(69000);
      check(b.canPay).isTrue();

      final fee = MyBooking.tryParse(
        bookingJson(
          status: 'cancelled',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
          carriedPaise: 64000,
        ),
      )!;
      check(fee.totalDuePaise).equals(69000);
    });

    test('an upcoming ride carries what will be added to its payment', () {
      final b = MyBooking.tryParse(bookingJson(carriedPaise: 5000))!;
      check(b.carriedPaise).equals(5000);
      check(b.canPay).isFalse();
    });

    test('nothing carried when the server leaves it out or garbles it', () {
      check(MyBooking.tryParse(bookingJson())!.carriedPaise).equals(0);
      for (final garbled in ['fifty', -100, null]) {
        final b = MyBooking.tryParse({
          ...bookingJson(status: 'completed', paymentStatus: 'due'),
          'carriedPaise': garbled,
        })!;
        check(because: '$garbled', b.carriedPaise).equals(0);
        check(b.totalDuePaise).equals(b.chargePaise);
      }
    });
  });

  group('booked time', () {
    test('a trip that ran past its booked time is told from one ended '
        'early', () {
      final over = MyBooking.tryParse(
        bookingJson(
          status: 'completed',
          farePaise: 96000,
          bookedFarePaise: 64000,
          startedAt: '2030-10-26T05:00:00Z',
          completedAt: '2030-10-26T08:40:00Z',
        ),
      )!;
      check(over.chargedByTime).isTrue();
      check(over.ranOver).isTrue();
      check(over.endedEarly).isFalse();
      // 3 h 40 min: four started hours.
      check(over.hoursUsed).equals(4);

      final early = MyBooking.tryParse(
        bookingJson(
          status: 'completed',
          farePaise: 24000,
          bookedFarePaise: 64000,
        ),
      )!;
      check(early.chargedByTime).isTrue();
      check(early.endedEarly).isTrue();
      check(early.ranOver).isFalse();

      // Charged exactly the booked fare for the time used: ended early.
      check(
        MyBooking.tryParse(
          bookingJson(
            status: 'completed',
            farePaise: 64000,
            bookedFarePaise: 64000,
          ),
        )!.endedEarly,
      ).isTrue();

      final asBooked = MyBooking.tryParse(bookingJson(status: 'completed'))!;
      check(asBooked.chargedByTime).isFalse();
      check(asBooked.ranOver).isFalse();
      check(asBooked.endedEarly).isFalse();
    });

    test('the hours used count each started hour, at least one', () {
      int? used(String start, String end) => MyBooking.tryParse(
        bookingJson(status: 'completed', startedAt: start, completedAt: end),
      )!.hoursUsed;
      check(used('2030-10-26T05:00:00Z', '2030-10-26T08:00:00Z')).equals(3);
      check(used('2030-10-26T05:00:00Z', '2030-10-26T08:00:01Z')).equals(4);
      check(used('2030-10-26T05:00:00Z', '2030-10-26T05:10:00Z')).equals(1);
      check(
        MyBooking.tryParse(bookingJson(status: 'completed'))!.hoursUsed,
      ).isNull();
    });

    test('a Round Trip is booked for its hours, the others for their '
        'window rounded up', () {
      check(
        MyBooking.tryParse(
          bookingJson(tripType: 'roundTrip', hours: 4),
        )!.bookedHours,
      ).equals(4);
      // 05:00 to 07:30: 2 h 30 min, so 3 h.
      check(MyBooking.tryParse(bookingJson())!.bookedHours).equals(3);
      check(
        MyBooking.tryParse(
          bookingJson(tripType: 'oneWay', endsAt: '2030-10-26T05:20:00Z'),
        )!.bookedHours,
      ).equals(1);
      check(
        MyBooking.tryParse({
          ...bookingJson(tripType: 'oneWay'),
          'endsAt': null,
        })!.bookedHours,
      ).isNull();
    });

    test('a trip on the road is past its booked time after the grace', () {
      // Booked 3 h, started 05:00: charged extra from 08:15.
      final b = MyBooking.tryParse(
        bookingJson(status: 'in_progress', startedAt: '2030-10-26T05:00:00Z'),
      )!;
      final from = DateTime.utc(2030, 10, 26, 8, 15);
      check(b.overtimeFrom).equals(from.toLocal());
      check(b.isPastBookedTime(DateTime.utc(2030, 10, 26, 8, 10))).isFalse();
      check(b.isPastBookedTime(from)).isFalse();
      check(b.isPastBookedTime(from.add(const Duration(seconds: 1)))).isTrue();

      final late = DateTime.utc(2030, 10, 27);
      // Not on the road, or no start time: never.
      check(
        MyBooking.tryParse(
          bookingJson(status: 'completed', startedAt: '2030-10-26T05:00:00Z'),
        )!.isPastBookedTime(late),
      ).isFalse();
      check(
        MyBooking.tryParse(
          bookingJson(status: 'in_progress'),
        )!.isPastBookedTime(late),
      ).isFalse();
    });
  });

  test('a driver nobody has rated yet has no average', () {
    final b = MyBooking.tryParse(bookingJson(ratingCount: 0))!;
    check(b.driverRating).isNull();
    check(b.driverRatingCount).equals(0);
  });

  test('the tracking window opens an hour before an accepted ride', () {
    final b = MyBooking.tryParse(bookingJson(status: 'accepted'))!;
    final start = b.scheduledAt;
    check(
      b.isInTrackingWindow(start.subtract(const Duration(minutes: 61))),
    ).isFalse();
    check(
      b.isInTrackingWindow(start.subtract(const Duration(minutes: 60))),
    ).isTrue();
    // At the pickup or on the trip it's always open; before a driver, never.
    final far = start.subtract(const Duration(days: 3));
    check(
      MyBooking.tryParse(
        bookingJson(status: 'arrived'),
      )!.isInTrackingWindow(far),
    ).isTrue();
    check(
      MyBooking.tryParse(
        bookingJson(status: 'in_progress'),
      )!.isInTrackingWindow(far),
    ).isTrue();
    check(
      MyBooking.tryParse(
        bookingJson(status: 'requested', withDriver: false),
      )!.isInTrackingWindow(start),
    ).isFalse();
  });

  test('the timeline ends where a cancelled ride stopped', () {
    final cancelled = MyBooking.tryParse(
      bookingJson(status: 'cancelled', cancelReason: 'Plans changed'),
    )!;
    final steps = rideTimeline(cancelled);
    check(
      steps.map((s) => s.label),
    ).deepEquals(['Booked', 'Driver assigned', 'Cancelled by you']);
    check(steps.last.state).equals(MilestoneState.ended);
    check(steps.last.detail).equals('Plans changed');

    final accepted = rideTimeline(MyBooking.tryParse(bookingJson())!);
    check(accepted.map((s) => s.state)).deepEquals([
      MilestoneState.done,
      MilestoneState.current,
      MilestoneState.upcoming,
      MilestoneState.upcoming,
      MilestoneState.upcoming,
    ]);
  });
}
