import 'package:checks/checks.dart';
import 'package:driver_app/core/config/app_config_providers.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/features/rides/view/ride_detail_screen.dart';
import 'package:driver_app/features/rides/view/widgets/help_safety_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'fakes.dart';

/// A ride on Mon 26 Oct 2026 at 9:00 AM local time.
Ride _ride({
  String id = '3f2a9c41-0b7e-4d2a-9a11-7c5e2b8d4f60',
  RideStatus status = RideStatus.accepted,
}) => Ride(
  id: id,
  kind: TripKind.roundTrip,
  status: status,
  scheduledAt: DateTime(2026, 10, 26, 9),
  endsAt: DateTime(2026, 10, 26, 12),
  farePaise: 34000,
  pickup: const RidePlace(
    address: 'Connaught Place, New Delhi, Delhi 110001, India',
    lat: 28.63,
    lng: 77.21,
  ),
);

const _driver = Driver(
  id: 'd1',
  phoneE164: '+919800000001',
  name: 'Ravi Kumar',
);

void main() {
  group('HelpSafety', () {
    test('the shared trip says when, where from, who and which booking', () {
      final text = HelpSafety.shareText(_ride(), driverFirstName: 'Ravi');

      check(text).contains('Mon, 26 Oct 2026, 9:00 AM');
      check(text).contains('Pickup: Connaught Place');
      check(text).not((it) => it.contains('110001'));
      check(text).contains('Driver: Ravi');
      check(text).contains('Booking: 3F2A9C41');
    });

    test('an unknown driver name is left out', () {
      check(HelpSafety.shareText(_ride())).not((it) => it.contains('Driver:'));
      check(
        HelpSafety.shareText(_ride(), driverFirstName: ' '),
      ).not((it) => it.contains('Driver:'));
    });

    test('first names', () {
      check(HelpSafety.firstName('Ravi Kumar')).equals('Ravi');
      check(HelpSafety.firstName('  Asha  ')).equals('Asha');
      check(HelpSafety.firstName('')).equals('');
    });

    test('the share link percent-encodes the text for WhatsApp', () {
      final link = HelpSafety.shareLink('Pickup: A & B\nBooking: X');
      check(
        link.toString(),
      ).equals('https://wa.me/?text=Pickup%3A%20A%20%26%20B%0ABooking%3A%20X');
    });

    test(
      'the support link uses the number as digits and names the booking',
      () {
        check(
          HelpSafety.supportLink('+91 90000-00001', 'r-42').toString(),
        ).equals('https://wa.me/919000000001?text=Booking%20r-42');
        check(HelpSafety.supportLink(null, 'r-42')).isNull();
        check(HelpSafety.supportLink('', 'r-42')).isNull();
      },
    );

    test('SOS dials 112', () {
      check(HelpSafety.emergencyCall.toString()).equals('tel:112');
    });
  });

  group('HelpSafetyRow', () {
    Future<(List<Uri>, List<String>)> pump(
      WidgetTester tester, {
      String? supportPhone,
      bool launches = true,
    }) async {
      final launched = <Uri>[];
      final copied = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: SkylineTheme.light(),
          home: Scaffold(
            body: HelpSafetyRow(
              ride: _ride(),
              driverFirstName: 'Ravi',
              supportPhone: supportPhone,
              launch: (uri) async {
                launched.add(uri);
                return launches;
              },
              copy: (text) async => copied.add(text),
            ),
          ),
        ),
      );
      return (launched, copied);
    }

    testWidgets('without a support number there is no Contact support', (
      tester,
    ) async {
      await pump(tester);

      check(find.text('Help & safety').evaluate()).isNotEmpty();
      check(find.text('Call 112').evaluate()).isNotEmpty();
      check(find.text('Share trip').evaluate()).isNotEmpty();
      check(find.text('Contact support').evaluate()).isEmpty();
    });

    testWidgets('with one, Contact support opens a WhatsApp chat', (
      tester,
    ) async {
      final (launched, _) = await pump(tester, supportPhone: '+919000000001');

      await tester.tap(find.text('Contact support'));
      await tester.pump();

      check(
        launched.single.toString(),
      ).startsWith('https://wa.me/919000000001?text=Booking%20');
    });

    testWidgets('Call 112 opens the dialer', (tester) async {
      final (launched, _) = await pump(tester);

      await tester.tap(find.text('Call 112'));
      await tester.pump();

      check(launched).deepEquals([Uri(scheme: 'tel', path: '112')]);
    });

    testWidgets('Share trip copies the text when WhatsApp is missing', (
      tester,
    ) async {
      final (launched, copied) = await pump(tester, launches: false);

      await tester.tap(find.text('Share trip'));
      await tester.pump();

      check(launched.single.host).equals('wa.me');
      check(copied.single).contains('Driver: Ravi');
      check(find.text('Trip details copied').evaluate()).isNotEmpty();
    });
  });

  group('on the ride detail screen', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      Ride ride, {
      String? supportPhone,
    }) async {
      tester.view.physicalSize = const Size(1800, 4400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final repo = FakeRidesRepository()..mine = [ride];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ridesRepositoryProvider.overrideWithValue(repo),
            locationServiceProvider.overrideWithValue(FakeLocationService()),
            driverSessionStorageProvider.overrideWithValue(_SessionStorage()),
            supportPhoneProvider.overrideWith((ref) async => supportPhone),
          ],
          child: MaterialApp(
            theme: SkylineTheme.light(),
            home: RideDetailScreen(ride: ride),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("the driver's own ride has Help & safety", (tester) async {
      await pumpScreen(tester, _ride(), supportPhone: '+919000000001');

      check(find.text('Help & safety').evaluate()).isNotEmpty();
      check(find.text('Contact support').evaluate()).isNotEmpty();
    });

    testWidgets('an open request does not', (tester) async {
      await pumpScreen(tester, _ride(status: RideStatus.requested));

      check(find.text('Help & safety').evaluate()).isEmpty();
    });
  });
}

class _SessionStorage implements DriverSessionStorage {
  @override
  Future<DriverAuthSession?> read() async =>
      const DriverAuthSession(token: 'tok', driver: _driver);

  @override
  Future<void> write(DriverAuthSession session) async {}

  @override
  Future<void> clear() async {}
}
