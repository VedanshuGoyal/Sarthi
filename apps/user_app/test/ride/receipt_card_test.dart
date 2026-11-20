import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/view/widgets/receipt_card.dart';
import 'package:user_app/features/ride/view/widgets/ride_format.dart';

import '../support/fake_booking_server.dart';

/// A booking as the server sends it, paid by one UPI payment of
/// [totalPaise] that paid [lines].
MyBooking _paid({
  String status = 'completed',
  int? cancellationFeePaise,
  int? totalPaise,
  List<Map<String, dynamic>> lines = const [],
}) => MyBooking.tryParse(
  bookingJson(
    status: status,
    tripType: 'roundTrip',
    paymentStatus: 'paid',
    cancellationFeePaise: cancellationFeePaise,
    payment: {
      'mode': 'UPI_INTENT',
      'utr': '412345678901',
      'merchantOrderId': 'MOJUD_b1_m3k9',
      'paidAt': '2030-10-26T08:00:00Z',
      'totalPaise': ?totalPaise,
      'lines': lines,
    },
  ),
)!;

Map<String, dynamic> _line(String id, String kind, String label, int paise) => {
  'bookingId': id,
  'kind': kind,
  'label': label,
  'amountPaise': paise,
};

Future<void> _pumpCard(WidgetTester tester, MyBooking booking) =>
    tester.pumpWidget(
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

bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  group('paid together', () {
    test('names what else the payment paid, by kind', () {
      final withFee = _paid(
        totalPaise: 69000,
        lines: [
          _line(
            'b0',
            'cancellation_fee',
            'Cancellation fee · Sun 15 Nov',
            5000,
          ),
          _line('b1', 'ride', 'Round trip · Sat 26 Oct', 64000),
        ],
      );
      check(
        RideFormat.paidTogether(withFee),
      ).equals('Paid ₹690 together with 1 cancellation fee.');

      final withRides = _paid(
        totalPaise: 112000,
        lines: [
          _line('b1', 'ride', 'Round trip · Sat 26 Oct', 64000),
          _line('b2', 'ride', 'One way · Fri 25 Oct', 24000),
          _line('b3', 'ride', 'Multi-stop · Thu 24 Oct', 24000),
        ],
      );
      check(
        RideFormat.paidTogether(withRides),
      ).equals('Paid ₹1120 together with 2 other rides.');

      // This booking is a fee: the ride is not an "other" one.
      final fee = _paid(
        status: 'cancelled',
        cancellationFeePaise: 5000,
        totalPaise: 34000,
        lines: [
          _line(
            'b1',
            'cancellation_fee',
            'Cancellation fee · Sat 26 Oct',
            5000,
          ),
          _line('b2', 'ride', 'One way · Fri 25 Oct', 24000),
          _line(
            'b3',
            'cancellation_fee',
            'Cancellation fee · Thu 24 Oct',
            5000,
          ),
        ],
      );
      check(
        RideFormat.paidTogether(fee),
      ).equals('Paid ₹340 together with 1 ride and 1 other cancellation fee.');
    });

    test('a payment for this booking alone says nothing more', () {
      check(
        RideFormat.paidTogether(
          _paid(
            totalPaise: 64000,
            lines: [_line('b1', 'ride', 'Round trip · Sat 26 Oct', 64000)],
          ),
        ),
      ).isNull();
      check(RideFormat.paidTogether(_paid())).isNull();
    });

    testWidgets('the receipt lists the other booking and the total paid', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _paid(
          totalPaise: 69000,
          lines: [
            _line(
              'b0',
              'cancellation_fee',
              'Cancellation fee · Sun 15 Nov',
              5000,
            ),
            _line('b1', 'ride', 'Round trip · Sat 26 Oct', 64000),
          ],
        ),
      );
      for (final text in [
        'Paid. Thank you!',
        'Paid ₹690 together with 1 cancellation fee.',
        'Fare',
        '₹640',
        'Cancellation fee · Sun 15 Nov',
        '₹50',
        'Total paid',
        '₹690',
        'Paid via',
        '412345678901',
      ]) {
        check(because: text, _shows(text)).isTrue();
      }
      // This ride isn't listed twice.
      check(_shows('Round trip · Sat 26 Oct')).isFalse();
    });

    testWidgets('a receipt for this booking alone has no total line', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _paid(
          totalPaise: 64000,
          lines: [_line('b1', 'ride', 'Round trip · Sat 26 Oct', 64000)],
        ),
      );
      check(_shows('Fare')).isTrue();
      check(_shows('₹640')).isTrue();
      check(_shows('Total paid')).isFalse();
      check(find.textContaining('together with').evaluate()).isEmpty();
    });

    testWidgets('many lines fit a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpCard(
        tester,
        _paid(
          totalPaise: 128000,
          lines: [
            for (var i = 0; i < 4; i++)
              _line('o$i', 'ride', 'Multi-stop · Wed 1$i Nov', 14750),
            _line(
              'f',
              'cancellation_fee',
              'Cancellation fee · Sun 15 Nov',
              5000,
            ),
            _line('b1', 'ride', 'Round trip · Sat 26 Oct', 64000),
          ],
        ),
      );
      check(
        _shows(
          'Paid ₹1280 together with 4 other rides and 1 cancellation fee.',
        ),
      ).isTrue();
      check(tester.takeException()).isNull();
    });
  });
}
