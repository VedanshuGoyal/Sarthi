// The ride screen in Hindi on narrow phones, for every trip type and every
// stage — the receipt with a payment that paid other rides too, the Pay
// button with dues carried from another ride, the cancellation fee, the
// end-trip dialog — failing on any layout exception.

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/ride_details_screen.dart';
import 'package:user_app/features/ride/view/widgets/end_trip_dialog.dart';
import 'package:user_app/features/ride/view/widgets/receipt_card.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/l10n/l10n.dart';

import '../support/fake_booking_server.dart';
import '../support/hindi.dart';

const _longStops = [
  'DLF Cyber Hub, DLF Cyber City, DLF Phase 2, Sector 24, Gurugram',
  'Ambience Mall, National Highway 48, Ambience Island, Gurugram',
  'Indira Gandhi International Airport Terminal 3, New Delhi',
];

/// [bookingJson] with a long-named driver, long places and, for
/// [tripType], the shape the server sends: no stops on a round trip or a
/// one-way, no destination on a round trip.
Map<String, dynamic> _ride({
  String id = 'b1',
  String status = 'accepted',
  String tripType = 'multiStop',
  String? scheduledAt,
  bool withDriver = true,
  String? otp,
  Map<String, dynamic>? myRating,
  String? startedAt,
  String? completedAt,
  String? cancelReason,
  String cancelledBy = 'customer',
  String? paymentStatus,
  Map<String, dynamic>? payment,
  Map<String, dynamic>? fareBreakdown,
  int farePaise = 164000,
  int? cancellationFeePaise,
  int? bookedFarePaise,
  int? carriedPaise,
}) {
  final json = bookingJson(
    id: id,
    status: status,
    tripType: tripType,
    scheduledAt: scheduledAt ?? '2030-10-26T05:00:00Z',
    withDriver: withDriver,
    otp: otp,
    myRating: myRating,
    startedAt: startedAt,
    completedAt: completedAt,
    cancelReason: cancelReason,
    cancelledBy: cancelledBy,
    paymentStatus: paymentStatus,
    payment: payment,
    fareBreakdown: fareBreakdown,
    farePaise: farePaise,
    cancellationFeePaise: cancellationFeePaise,
    bookedFarePaise: bookedFarePaise,
    carriedPaise: carriedPaise,
    hours: tripType == 'roundTrip' ? 4 : null,
  );
  return {
    ...json,
    'pickup': {
      'address':
          'Tower B, DLF Magnolias, Golf Course Road, Sector 42, Gurugram, '
          'Haryana 122002',
      'lat': 28.6315,
      'lng': 77.2167,
    },
    if (withDriver)
      'driver': {
        ...json['driver'] as Map<String, dynamic>,
        'name': 'Rameshwar Prasad Chaurasia',
      },
    if (status == 'arrived') 'arrivedAt': '2030-10-25T05:30:00Z',
    'destination': tripType == 'roundTrip'
        ? null
        : {
            'address': 'Indira Gandhi International Airport Terminal 3',
            'lat': 28.55,
            'lng': 77.08,
          },
    'stopCount': tripType == 'multiStop' ? _longStops.length : 0,
    'stops': tripType != 'multiStop'
        ? const []
        : [
            for (final (i, place) in _longStops.indexed)
              {
                'place': {'address': place, 'lat': 28.5, 'lng': 77.1},
                'task': 'Pick up the parcel from the reception desk and sign',
                'departBy': '2030-10-26T0${6 + i}:00:00Z',
              },
          ],
  };
}

/// The driver's latest fix, [metres] north of the pickup and 10 s old.
Map<String, dynamic> _fix(double metres) => {
  'lat': 28.6315 + metres / 111000,
  'lng': 77.2167,
  'updatedAt': DateTime.now()
      .toUtc()
      .subtract(const Duration(seconds: 10))
      .toIso8601String(),
};

void main() {
  final hi = lookupAppLocalizations(const Locale('hi'));

  tearDown(L10n.reset);

  /// Pumps the ride screen of [id] in Hindi over [server], with the list
  /// loaded as Activity would have it.
  Future<void> pumpRide(
    WidgetTester tester,
    FakeBookingServer server, {
    required double width,
    String id = 'b1',
    bool settle = true,
  }) async {
    // A fresh scope each time: the ride's view model is cached by id.
    await tester.pumpWidget(const SizedBox());
    final repo = server.repository();
    final bookings = MyBookingsViewModel(repository: repo);
    await tester.runAsync(bookings.load);
    await pumpHindi(
      tester,
      RideDetailsScreen(bookingId: id),
      width: width,
      settle: settle,
      overrides: [
        bookingRepositoryProvider.overrideWithValue(repo),
        myBookingsViewModelProvider.overrideWith((ref) => bookings),
      ],
    );
    // A due ride re-checks its payment in the background; let it land.
    if (!settle) await tester.pump(const Duration(milliseconds: 100));
  }

  for (final width in hindiWidths) {
    group('Hindi at ${width.toInt()} dp wide:', () {
      testWidgets('each trip type, booked and upcoming', (tester) async {
        for (final type in const ['roundTrip', 'oneWay', 'multiStop']) {
          await pumpRide(
            tester,
            FakeBookingServer([_ride(tripType: type, otp: '4821')]),
            width: width,
          );
          checkHindiFits(tester);
          check(find.text(hi.startCodeTitle).evaluate()).isNotEmpty();
        }
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('finding a driver, and no driver found', (tester) async {
        for (final status in const ['requested', 'expired']) {
          await pumpRide(
            tester,
            FakeBookingServer([_ride(status: status, withDriver: false)]),
            width: width,
          );
          checkHindiFits(tester);
        }
        check(find.text(hi.rideTimelineNoDriverDetail).evaluate()).isNotEmpty();
      });

      testWidgets('driver assigned with dues carried, and on the way', (
        tester,
      ) async {
        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(otp: '4821', carriedPaise: 5000),
            _ride(
              id: 'fee',
              status: 'cancelled',
              cancellationFeePaise: 5000,
              paymentStatus: 'due',
              scheduledAt: '2030-10-20T05:00:00Z',
            ),
          ]),
          width: width,
        );
        checkHindiFits(tester);

        // Half an hour before the start: the driver's location is shown.
        final soon = DateTime.now().toUtc().add(const Duration(minutes: 30));
        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(otp: '4821', scheduledAt: soon.toIso8601String()),
          ])..location = _fix(2300),
          width: width,
        );
        checkHindiFits(tester);
        check(
          find.textContaining(hi.rideAgeSeconds(10)).evaluate(),
        ).isNotEmpty();
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('driver at the pickup, and on a trip past its time', (
        tester,
      ) async {
        await pumpRide(
          tester,
          FakeBookingServer([_ride(status: 'arrived', otp: '4821')])
            ..location = _fix(40),
          width: width,
        );
        checkHindiFits(tester);

        final started = DateTime.now().toUtc().subtract(
          const Duration(hours: 3, minutes: 20),
        );
        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(status: 'in_progress', startedAt: started.toIso8601String()),
          ])..location = _fix(5000),
          width: width,
        );
        checkHindiFits(tester);
        check(find.text(hi.fmtPastBookedTime).evaluate()).isNotEmpty();
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('the end-trip dialog', (tester) async {
        await pumpRide(
          tester,
          FakeBookingServer([_ride(status: 'in_progress')]),
          width: width,
          settle: false,
        );
        final end = find.text(hi.endTripNow);
        await tester.ensureVisible(end);
        await tester.pump();
        await tester.tap(end);
        await tester.pump(const Duration(milliseconds: 400));
        check(find.byType(EndTripDialog).evaluate()).isNotEmpty();
        checkHindiFits(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('completed and due: Pay, with a ride carried, and the '
          'rating card', (tester) async {
        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(
              status: 'completed',
              tripType: 'oneWay',
              paymentStatus: 'due',
              carriedPaise: 12000,
            ),
          ]),
          width: width,
          settle: false,
        );
        checkHindiFits(tester);
        check(
          find.text(hi.rideDetailsPayByUpi('₹1760')).evaluate(),
        ).isNotEmpty();
        check(find.text(hi.rideDetailsRateDriver).evaluate()).isNotEmpty();
      });

      testWidgets('completed and paid: the receipt with other rides and a '
          'fee paid together, the night surcharge, and the stars given', (
        tester,
      ) async {
        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(
              status: 'completed',
              tripType: 'roundTrip',
              paymentStatus: 'paid',
              myRating: {
                'stars': 4,
                'note': 'Drove carefully and waited patiently at every stop',
              },
              fareBreakdown: {'basePaise': 144000, 'nightPaise': 20000},
              payment: {
                'mode': 'UPI_INTENT',
                'utr': '412345678901',
                'merchantOrderId':
                    'MOJUD_9f1c2a7b3d4e5f60718293a4b5c6d7e8_m3k9x2',
                'paidAt': '2030-10-26T08:00:00Z',
                'totalPaise': 207000,
                'lines': [
                  {
                    'bookingId': 'b0',
                    'kind': 'ride',
                    'label': 'One way · Fri 25 Oct',
                    'amountPaise': 24000,
                  },
                  {'bookingId': 'b2', 'kind': 'ride', 'amountPaise': 14000},
                  {
                    'bookingId': 'b3',
                    'kind': 'cancellation_fee',
                    'amountPaise': 5000,
                  },
                  {'bookingId': 'b1', 'kind': 'ride', 'amountPaise': 164000},
                ],
              },
            ),
          ]),
          width: width,
        );
        checkHindiFits(tester);
        final receipt = find.byType(ReceiptCard);
        for (final text in [
          hi.fmtPaidTogether(
            '₹2070',
            hi.fmtListAnd(hi.fmtOtherRides(2), hi.fmtCancellationFeeCount(1)),
          ),
          hi.receiptNightSurcharge,
          hi.paymentLineRide,
          hi.paymentLineCancellationFee,
          hi.receiptTotalPaid,
        ]) {
          check(
            because: text,
            find.descendant(of: receipt, matching: find.text(text)).evaluate(),
          ).isNotEmpty();
        }
      });

      testWidgets('a trip ended early and one that ran over, paid', (
        tester,
      ) async {
        for (final (fare, booked) in const [(24000, 64000), (96000, 64000)]) {
          await pumpRide(
            tester,
            FakeBookingServer([
              _ride(
                status: 'completed',
                farePaise: fare,
                bookedFarePaise: booked,
                startedAt: '2030-10-26T05:00:00Z',
                completedAt: '2030-10-26T08:40:00Z',
                paymentStatus: 'paid',
                payment: {'mode': 'CASH', 'paidAt': '2030-10-26T09:00:00Z'},
              ),
            ]),
            width: width,
          );
          checkHindiFits(tester);
          check(find.text(hi.receiptFareForTimeUsed).evaluate()).isNotEmpty();
        }
      });

      testWidgets('cancelled with the ₹50 fee due, paid, and as a no-show', (
        tester,
      ) async {
        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(
              status: 'cancelled',
              cancelReason: 'Driver is not responding',
              cancellationFeePaise: 5000,
              paymentStatus: 'due',
            ),
          ]),
          width: width,
          settle: false,
        );
        checkHindiFits(tester);
        check(find.text(hi.rideDetailsPayFeeTitle).evaluate()).isNotEmpty();
        check(
          find.text(hi.cancelReasonDriverNotResponding).evaluate(),
        ).isNotEmpty();

        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(
              status: 'cancelled',
              cancelReason: 'Plans changed',
              cancellationFeePaise: 5000,
              paymentStatus: 'paid',
              payment: {'mode': 'UPI_QR', 'paidAt': '2030-10-25T07:00:00Z'},
            ),
          ]),
          width: width,
        );
        checkHindiFits(tester);

        await pumpRide(
          tester,
          FakeBookingServer([
            _ride(
              status: 'cancelled',
              cancelledBy: 'no_show',
              cancelReason: 'The driver waited at the pickup until 10:15 AM',
            ),
          ]),
          width: width,
        );
        checkHindiFits(tester);
      });
    });
  }
}
