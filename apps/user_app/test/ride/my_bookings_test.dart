import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/activity_panel.dart';
import 'package:user_app/features/ride/view/widgets/my_ride_card.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';

Map<String, dynamic> _booking({
  required String id,
  required String status,
  // Far ahead, so an open request isn't read as expired whenever tests run.
  String scheduledAt = '2030-10-26T09:00:00+05:30',
  bool withDriver = false,
  String? otp,
}) => {
  'id': id,
  'tripType': 'oneWay',
  'status': status,
  'scheduledAt': scheduledAt,
  'endsAt': '2026-10-26T10:00:00+05:30',
  'farePaise': 19600,
  'fareEstimated': true,
  'pickup': {'address': 'DLF Cyber Hub, Gurugram', 'lat': 28.49, 'lng': 77.08},
  'destination': {'address': 'Hauz Khas Village', 'lat': 28.55, 'lng': 77.19},
  'car': {'registration': 'HR26DK8337', 'carType': 'luxury'},
  if (withDriver)
    'driver': {'name': 'Ravi Kumar', 'phoneE164': '+919800000001'},
  'startOtp': ?otp,
  'createdAt': '2026-10-25T04:35:00Z',
};

BookingRepository _repo(Object body, {int status = 200}) => BookingRepository(
  baseUrl: 'http://api',
  tokenGetter: () => 'tok',
  client: MockClient((request) async {
    check(request.method).equals('GET');
    check(request.url.path).equals('/me/bookings');
    check(request.headers['Authorization']).equals('Bearer tok');
    return http.Response(jsonEncode(body), status);
  }),
);

void main() {
  test('myBookings parses status, driver and start code', () async {
    final bookings = await _repo({
      'bookings': [
        _booking(id: 'a', status: 'accepted', withDriver: true, otp: '4821'),
        {'id': 'broken'},
      ],
    }).myBookings();

    check(bookings).length.equals(1);
    final b = bookings.single;
    check(b.tripType).equals(TripType.oneWay);
    check(b.status).equals(BookingStatus.accepted);
    check(b.driverName).equals('Ravi Kumar');
    check(b.startOtp).equals('4821');
    check(b.destinationAddress).equals('Hauz Khas Village');
    check(b.fareRupees).equals(196);
  });

  test('a failed load surfaces a message instead of throwing', () async {
    final vm = MyBookingsViewModel(repository: _repo({}, status: 500));
    await vm.load();
    check(vm.error).isNotNull();
    check(vm.active).isEmpty();
  });

  test('active leaves out finished rides and puts the soonest first', () async {
    final vm = MyBookingsViewModel(
      repository: _repo({
        'bookings': [
          _booking(
            id: 'later',
            status: 'requested',
            scheduledAt: '2030-10-27T09:00:00+05:30',
          ),
          _booking(id: 'done', status: 'completed'),
          _booking(id: 'soon', status: 'arrived', withDriver: true, otp: '1'),
        ],
      }),
    );
    await vm.load();
    check(vm.active.map((b) => b.id)).deepEquals(['soon', 'later']);
  });

  test('past holds finished and cancelled rides, latest first', () async {
    final vm = MyBookingsViewModel(
      repository: _repo({
        'bookings': [
          _booking(
            id: 'old',
            status: 'completed',
            scheduledAt: '2026-10-20T09:00:00+05:30',
          ),
          _booking(id: 'open', status: 'requested'),
          _booking(
            id: 'new',
            status: 'cancelled',
            scheduledAt: '2026-10-24T09:00:00+05:30',
          ),
        ],
      }),
    );
    check(vm.hasLoaded).isFalse();
    await vm.load();
    check(vm.hasLoaded).isTrue();
    check(vm.past.map((b) => b.id)).deepEquals(['new', 'old']);
  });

  Future<void> pumpCard(WidgetTester tester, MyBooking booking) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SkylineTheme.light(),
        home: Scaffold(body: MyRideCard(booking: booking)),
      ),
    );
  }

  testWidgets('an assigned ride shows the driver and the start code', (
    tester,
  ) async {
    await pumpCard(
      tester,
      MyBooking.tryParse(
        _booking(id: 'a', status: 'accepted', withDriver: true, otp: '4821'),
      )!,
    );
    check(find.text('Driver assigned').evaluate()).isNotEmpty();
    check(find.text('Ravi Kumar is your driver').evaluate()).isNotEmpty();
    check(find.text('4 8 2 1').evaluate()).isNotEmpty();
    check(find.byTooltip('Call driver').evaluate()).isNotEmpty();
  });

  testWidgets('an open booking says it is finding a driver', (tester) async {
    await pumpCard(
      tester,
      MyBooking.tryParse(_booking(id: 'a', status: 'requested'))!,
    );
    check(find.text('Finding a driver').evaluate()).isNotEmpty();
    check(
      find.textContaining('as soon as one accepts').evaluate(),
    ).isNotEmpty();
    check(find.text('Start code').evaluate()).isEmpty();
  });

  test('an open request reads as expired once it closes to drivers', () {
    final json = _booking(
      id: 'a',
      status: 'requested',
      scheduledAt: '2026-10-26T09:00:00+05:30',
    );
    final start = DateTime.parse('2026-10-26T09:00:00+05:30');

    check(
      MyBooking.tryParse(
        json,
        now: start.subtract(const Duration(minutes: 31)),
      )!.status,
    ).equals(BookingStatus.requested);
    final late = MyBooking.tryParse(
      json,
      now: start.subtract(const Duration(minutes: 29)),
    )!;
    check(late.status).equals(BookingStatus.expired);
    check(late.status.isActive).isFalse();

    // The server's own "expired" reads the same, and a taken ride never
    // expires.
    check(
      MyBooking.tryParse(_booking(id: 'b', status: 'expired'))!.status,
    ).equals(BookingStatus.expired);
    check(
      MyBooking.tryParse(
        _booking(id: 'c', status: 'accepted', withDriver: true),
        now: start,
      )!.status,
    ).equals(BookingStatus.accepted);
  });

  testWidgets('an expired booking says no driver was found', (tester) async {
    await pumpCard(
      tester,
      MyBooking.tryParse(_booking(id: 'a', status: 'expired'))!,
    );
    check(find.text('No driver found').evaluate()).isNotEmpty();
    check(find.textContaining('book again').evaluate()).isNotEmpty();
    check(find.textContaining('as soon as one accepts').evaluate()).isEmpty();
  });

  testWidgets('a completed ride shows who drove and the fare', (tester) async {
    await pumpCard(
      tester,
      MyBooking.tryParse(
        _booking(id: 'a', status: 'completed', withDriver: true),
      )!,
    );
    check(find.text('Completed').evaluate()).isNotEmpty();
    check(find.text('Driven by Ravi Kumar').evaluate()).isNotEmpty();
    check(find.text('≈ ₹196').evaluate()).isNotEmpty();
    check(find.byTooltip('Call driver').evaluate()).isEmpty();
  });

  testWidgets('Activity splits rides into Upcoming and Completed', (
    tester,
  ) async {
    final vm = MyBookingsViewModel(
      repository: _repo({
        'bookings': [
          _booking(id: 'a', status: 'accepted', withDriver: true, otp: '4821'),
          _booking(id: 'b', status: 'completed', withDriver: true),
          _booking(id: 'c', status: 'cancelled'),
        ],
      }),
    );
    await vm.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [myBookingsViewModelProvider.overrideWith((ref) => vm)],
        child: MaterialApp(
          theme: SkylineTheme.light(),
          home: const ActivityPanel(),
        ),
      ),
    );

    check(find.text('Upcoming · 1').evaluate()).isNotEmpty();
    check(find.text('Completed · 2').evaluate()).isNotEmpty();
    check(find.text('4 8 2 1').evaluate()).isNotEmpty();

    await tester.tap(find.text('Completed · 2'));
    await tester.pumpAndSettle();
    check(find.text('Driven by Ravi Kumar').evaluate()).isNotEmpty();
    check(find.text('Cancelled').evaluate()).isNotEmpty();
  });
}
