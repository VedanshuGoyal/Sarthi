import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/core/config/app_config_repository.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/view/widgets/help_safety_row.dart';
import 'package:user_app/l10n/l10n.dart';

MyBooking _booking({
  BookingStatus status = BookingStatus.accepted,
  String? driverName = 'Ravi Kumar',
}) => MyBooking(
  id: '3f2a9c1b-0000-4000-8000-000000000001',
  tripType: TripType.roundTrip,
  status: status,
  // A Wednesday.
  scheduledAt: DateTime(2026, 11, 18, 9, 30),
  pickupAddress: 'Indiranagar, Bengaluru',
  farePaise: 24000,
  driverName: driverName,
);

/// A config endpoint answering with [status] and [body].
AppConfigRepository _config(
  int status,
  Object? body, {
  String fallback = '',
  List<Uri>? calls,
}) => AppConfigRepository(
  baseUrl: 'https://api.example.test',
  fallbackSupportPhone: fallback,
  client: MockClient((request) async {
    calls?.add(request.url);
    return http.Response(jsonEncode(body), status);
  }),
);

void main() {
  group('support phone', () {
    test("the server's number wins over this build's", () async {
      final phone = await _config(200, {
        'supportPhone': '+91 98765 43210',
      }, fallback: '+919000000000').supportPhone();
      check(phone).equals('+919876543210');
    });

    test("falls back to this build's number", () async {
      check(
        await _config(200, {
          'supportPhone': '',
        }, fallback: '+919000000000').supportPhone(),
      ).equals('+919000000000');
      check(
        await _config(404, {
          'error': 'no',
        }, fallback: '919000000000').supportPhone(),
      ).equals('+919000000000');
    });

    test('with neither, there is no number (the button hides)', () async {
      check(await _config(200, {'other': 1}).supportPhone()).isNull();
      check(await _config(500, null).supportPhone()).isNull();
      check(resolveSupportPhone('12', fallback: 'abc')).isNull();
    });

    test('a failed request counts as not configured', () async {
      final repo = AppConfigRepository(
        baseUrl: 'https://api.example.test',
        fallbackSupportPhone: '',
        client: MockClient((_) => throw http.ClientException('offline')),
      );
      check(await repo.supportPhone()).isNull();
    });

    test('is fetched once per app session', () async {
      final calls = <Uri>[];
      final repo = _config(200, {
        'supportPhone': '+919876543210',
      }, calls: calls);
      await repo.supportPhone();
      await repo.supportPhone();
      check(calls).single.has((u) => u.path, 'path').equals('/app/config');
    });
  });

  group('HelpSafety text and links', () {
    test('the shared trip says when, where from, who and which ride', () {
      check(HelpSafety.shareText(_booking())).equals(
        'My MOJUD trip\n'
        'When: Wed 18 Nov, 9:30 AM\n'
        'Pickup: Indiranagar, Bengaluru\n'
        'Driver: Ravi\n'
        'Booking: 3F2A9C1B',
      );
    });

    test('before a driver is assigned the driver line is left out', () {
      check(
        HelpSafety.shareText(
          _booking(status: BookingStatus.requested, driverName: null),
        ),
      ).not((s) => s.contains('Driver'));
    });

    test('times read in 12-hour form', () {
      check(
        HelpSafety.formatWhen(DateTime(2026, 11, 16, 0, 5)),
      ).equals('Mon 16 Nov, 12:05 AM');
      check(
        HelpSafety.formatWhen(DateTime(2026, 11, 22, 18, 0)),
      ).equals('Sun 22 Nov, 6:00 PM');
    });

    test('share and support links are WhatsApp, text encoded', () {
      check(
        HelpSafety.shareUri('Hi there\nBooking: X').toString(),
      ).equals('https://wa.me/?text=Hi%20there%0ABooking%3A%20X');
      check(
        HelpSafety.supportUri('+91 98765 43210', 'b-1').toString(),
      ).equals('https://wa.me/919876543210?text=Booking%20b-1');
      check(HelpSafety.sosUri.toString()).equals('tel:112');
    });
  });

  group('HelpSafetyRow', () {
    Future<void> pump(
      WidgetTester tester,
      MyBooking booking, {
      String? supportPhone,
      List<Uri>? launched,
      bool canLaunch = true,
      List<String>? copied,
    }) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SkylineTheme.light(),
        home: Scaffold(
          body: HelpSafetyRow(
            booking: booking,
            supportPhone: supportPhone,
            launch: (uri) async {
              launched?.add(uri);
              return canLaunch;
            },
            copy: (text) async => copied?.add(text),
          ),
        ),
      ),
    );

    bool shows(String text) => find.text(text).evaluate().isNotEmpty;

    testWidgets('an upcoming ride offers SOS, sharing and support', (
      tester,
    ) async {
      final launched = <Uri>[];
      await pump(
        tester,
        _booking(),
        supportPhone: '+919876543210',
        launched: launched,
      );
      check(shows('Help & safety')).isTrue();

      await tester.tap(find.text('Call 112'));
      await tester.tap(find.text('Contact support'));
      await tester.pump();

      check(launched).deepEquals([
        Uri.parse('tel:112'),
        HelpSafety.supportUri('+919876543210', _booking().id),
      ]);
    });

    testWidgets('without a support number the button is hidden', (
      tester,
    ) async {
      await pump(tester, _booking());
      check(shows('Call 112')).isTrue();
      check(shows('Share trip')).isTrue();
      check(shows('Contact support')).isFalse();
    });

    testWidgets('a finished ride keeps only support', (tester) async {
      await pump(
        tester,
        _booking(status: BookingStatus.completed),
        supportPhone: '+919876543210',
      );
      check(shows('Call 112')).isFalse();
      check(shows('Share trip')).isFalse();
      check(shows('Contact support')).isTrue();

      await pump(tester, _booking(status: BookingStatus.cancelled));
      check(shows('Help & safety')).isFalse();
    });

    testWidgets('without WhatsApp the trip is copied instead', (tester) async {
      final copied = <String>[];
      await pump(tester, _booking(), canLaunch: false, copied: copied);

      await tester.tap(find.text('Share trip'));
      await tester.pump();

      check(copied).single.equals(HelpSafety.shareText(_booking()));
      check(shows('Trip details copied')).isTrue();
    });
  });
}
