// The Activity tab and what opens from it — every kind of ride card, the
// cancel sheet, the rating sheet, Help & safety — in Hindi on narrow
// phones; fails on any layout exception (see test/support/hindi.dart).

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/activity_panel.dart';
import 'package:user_app/features/ride/view/rate_ride_sheet.dart';
import 'package:user_app/features/ride/view/widgets/cancel_ride_sheet.dart';
import 'package:user_app/features/ride/view/widgets/help_safety_row.dart';
import 'package:user_app/features/ride/view/widgets/my_ride_card.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/l10n/l10n.dart';

import '../support/fake_booking_server.dart';
import '../support/hindi.dart';

const _longName = 'Rameshwar Prasad Chaurasia';

const _longReason =
    'The driver called to say he would be an hour late, and I need to '
    'leave for the airport before that, so I have booked a taxi instead.';

/// [bookingJson] with a long-named driver, as the widest rows get.
Map<String, dynamic> _ride({
  required String id,
  required String status,
  String tripType = 'multiStop',
  bool withDriver = true,
  String? otp,
  Map<String, dynamic>? myRating,
  String? cancelReason,
  String cancelledBy = 'customer',
  String? paymentStatus,
  int farePaise = 1234500,
  int? cancellationFeePaise,
  int? bookedFarePaise,
  int? carriedPaise,
  int? hours,
  String? startedAt,
  String? completedAt,
}) {
  final json = bookingJson(
    id: id,
    status: status,
    tripType: tripType,
    withDriver: withDriver,
    otp: otp,
    myRating: myRating,
    cancelReason: cancelReason,
    cancelledBy: cancelledBy,
    paymentStatus: paymentStatus,
    farePaise: farePaise,
    cancellationFeePaise: cancellationFeePaise,
    bookedFarePaise: bookedFarePaise,
    carriedPaise: carriedPaise,
    hours: hours,
    startedAt: startedAt,
    completedAt: completedAt,
  );
  if (withDriver) {
    (json['driver'] as Map<String, dynamic>)['name'] = _longName;
  }
  json['pickup'] = {
    'address':
        'DLF Cyber Hub, DLF Cyber City, DLF Phase 2, Sector 24, Gurugram, '
        'Haryana 122002',
    'lat': 28.4950,
    'lng': 77.0895,
  };
  return json;
}

/// Every kind of card the Activity tab shows, upcoming and past.
List<Map<String, dynamic>> _everyRide() => [
  // Upcoming.
  _ride(id: 'u1', status: 'requested', tripType: 'oneWay', withDriver: false),
  _ride(
    id: 'u2',
    status: 'accepted',
    tripType: 'roundTrip',
    hours: 4,
    otp: '4821',
    carriedPaise: 123400,
  ),
  _ride(id: 'u3', status: 'arrived', otp: '9930'),
  _ride(
    id: 'u4',
    status: 'in_progress',
    tripType: 'roundTrip',
    hours: 2,
    startedAt: '2030-10-26T05:05:00Z',
  ),
  // Past.
  _ride(
    id: 'p1',
    status: 'completed',
    paymentStatus: 'due',
    carriedPaise: 5000,
    completedAt: '2030-10-26T07:40:00Z',
  ),
  _ride(
    id: 'p2',
    status: 'completed',
    tripType: 'oneWay',
    paymentStatus: 'paid',
    myRating: {'stars': 4, 'note': 'Careful driver'},
    completedAt: '2030-10-26T07:40:00Z',
  ),
  _ride(
    id: 'p3',
    status: 'completed',
    tripType: 'roundTrip',
    hours: 4,
    paymentStatus: 'paid',
    completedAt: '2030-10-26T07:40:00Z',
  ),
  _ride(
    id: 'p4',
    status: 'completed',
    tripType: 'roundTrip',
    hours: 4,
    farePaise: 32000,
    bookedFarePaise: 64000,
    paymentStatus: 'due',
    completedAt: '2030-10-26T07:00:00Z',
  ),
  _ride(
    id: 'p5',
    status: 'completed',
    tripType: 'roundTrip',
    hours: 4,
    farePaise: 1296000,
    bookedFarePaise: 864000,
    paymentStatus: 'paid',
    completedAt: '2030-10-26T11:00:00Z',
  ),
  _ride(
    id: 'p6',
    status: 'cancelled',
    cancelReason: 'Plans changed',
    cancellationFeePaise: 5000,
    paymentStatus: 'due',
  ),
  _ride(id: 'p7', status: 'cancelled', cancelReason: _longReason),
  _ride(id: 'p8', status: 'cancelled', cancelledBy: 'driver'),
  _ride(
    id: 'p9',
    status: 'cancelled',
    cancelledBy: 'no_show',
    cancellationFeePaise: 5000,
    paymentStatus: 'paid',
  ),
  _ride(id: 'p10', status: 'expired', tripType: 'oneWay', withDriver: false),
];

void main() {
  tearDown(L10n.reset);

  /// Pumps [home] in Hindi over [server], then loads the rides list as the
  /// shell would — once the app is in Hindi, so its messages are too.
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required double width,
    FakeBookingServer? server,
    BookingRepository? repository,
    double height = 2400,
  }) async {
    final repo = repository ?? (server ?? FakeBookingServer([])).repository();
    final bookings = MyBookingsViewModel(repository: repo);
    await pumpHindi(
      tester,
      home,
      width: width,
      height: height,
      // A ride still finding a driver spins forever: don't wait to settle.
      settle: false,
      overrides: [
        bookingRepositoryProvider.overrideWithValue(repo),
        myBookingsViewModelProvider.overrideWith((ref) => bookings),
      ],
    );
    await tester.runAsync(bookings.load);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Opens the Activity tab at [index] and lets it slide in.
  Future<void> openTab(WidgetTester tester, int index) async {
    await tester.tap(find.byType(Tab).at(index));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  MyBooking booking(Map<String, dynamic> json) => MyBooking.tryParse(json)!;

  for (final width in hindiWidths) {
    group('Hindi at ${width.toInt()} dp wide:', () {
      testWidgets('Activity with every kind of ride, both tabs', (
        tester,
      ) async {
        await pump(
          tester,
          const ActivityPanel(),
          width: width,
          server: FakeBookingServer(_everyRide()),
          height: 4800,
        );
        check(find.byType(MyRideCard).evaluate().length).equals(4);
        check(find.text('आने वाली · 4').evaluate()).isNotEmpty();
        checkHindiFits(tester);

        await openTab(tester, 1);
        check(find.byType(MyRideCard).evaluate().length).equals(10);
        check(find.text('पिछली · 10').evaluate()).isNotEmpty();
        // The Pay button, with what it also collects from another ride.
        check(
          find.textContaining('UPI से ₹12395 का पेमेंट करें').evaluate(),
        ).isNotEmpty();
        checkHindiFits(tester);
      });

      testWidgets('Activity with no rides, and when loading fails', (
        tester,
      ) async {
        await pump(tester, const ActivityPanel(), width: width);
        check(find.text('कोई आने वाली राइड नहीं').evaluate()).isNotEmpty();
        checkHindiFits(tester);
        await openTab(tester, 1);
        checkHindiFits(tester);

        // A fresh ProviderScope, for a list that fails to load.
        await tester.pumpWidget(const SizedBox());
        await pump(
          tester,
          const ActivityPanel(),
          width: width,
          repository: BookingRepository(
            baseUrl: 'http://api',
            tokenGetter: () => 'tok',
            client: MockClient((_) async => http.Response('', 500)),
          ),
        );
        check(
          find.text('आपकी राइड लोड नहीं हो पाईं (500)।').evaluate(),
        ).isNotEmpty();
        checkHindiFits(tester);
      });

      testWidgets('the cancel sheet before and after the driver arrives', (
        tester,
      ) async {
        for (final (json, fee, reason) in [
          (_ride(id: 'c1', status: 'requested', withDriver: false), 0, null),
          (_ride(id: 'c2', status: 'accepted'), 0, 'Plans changed'),
          (_ride(id: 'c3', status: 'arrived'), 0, null),
          (_ride(id: 'c4', status: 'arrived'), 5000, _longReason),
          (_ride(id: 'c5', status: 'arrived', withDriver: false), 5000, null),
        ]) {
          await pump(
            tester,
            Scaffold(
              body: CancelRideSheet(
                // A fresh sheet each time, so its reason starts as given.
                key: ValueKey(json['id']),
                booking: booking(json),
                feePaise: fee,
                initialReason: reason,
              ),
            ),
            width: width,
          );
          checkHindiFits(tester);
          if (reason == _longReason) {
            // "Other", with the customer's own words in its field.
            check(find.text('कुछ और').evaluate()).isNotEmpty();
            check(find.text(_longReason).evaluate()).isNotEmpty();
          }
          if (fee > 0) {
            check(find.text('कैंसल करें और ₹50 दें').evaluate()).isNotEmpty();
          } else {
            check(find.text('राइड कैंसल करें').evaluate()).isNotEmpty();
          }
        }
      });

      testWidgets('the rating sheet', (tester) async {
        final done = _ride(
          id: 'r1',
          status: 'completed',
          paymentStatus: 'paid',
          completedAt: '2030-10-26T07:40:00Z',
        );
        await pump(
          tester,
          Scaffold(body: RateRideSheet(booking: booking(done))),
          width: width,
          server: FakeBookingServer([done]),
        );
        check(
          find.text('Rameshwar के साथ आपकी ट्रिप कैसी रही?').evaluate(),
        ).isNotEmpty();
        checkHindiFits(tester);
      });

      testWidgets('Help & safety, and the trip it shares', (tester) async {
        final ride = booking(_ride(id: 'h1', status: 'accepted'));
        await pump(
          tester,
          Scaffold(
            body: HelpSafetyRow(booking: ride, supportPhone: '+919000000000'),
          ),
          width: width,
        );
        checkHindiFits(tester);
        check(HelpSafety.shareText(ride)).contains('कब: ');
      });
    });
  }
}
