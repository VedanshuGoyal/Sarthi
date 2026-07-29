import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/view/widgets/vast_quiet/vast_quiet.dart';

/// Smoke coverage for the Vast Quiet card set: each card renders under the
/// ride-flow theme with bounded constraints and throws no layout/paint
/// exception. The custom-painted and animated cards (hatch, progress rail,
/// action bar, shimmer) are the ones worth guarding here.
void main() {
  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: vastQuietTheme(),
        home: Scaffold(
          body: Center(
            child: SingleChildScrollView(child: Center(child: card)),
          ),
        ),
      ),
    );
    // A couple of frames covers the entry animations without settling the
    // skeleton's perpetual shimmer (which would hang pumpAndSettle).
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  }

  void noop() {}

  testWidgets('1a — ride class picker', (tester) async {
    await pumpCard(
      tester,
      RideClassPicker(
        options: const [
          RideClassOption(
            id: 'a',
            name: 'Glide',
            meta: '4 SEATS · 3 MIN',
            price: '£12.80',
            note: 'STANDARD',
          ),
          RideClassOption(
            id: 'b',
            name: 'Glide Quiet',
            meta: '4 SEATS · 5 MIN',
            price: '£18.40',
            note: 'NO SMALL TALK',
          ),
        ],
        selectedId: 'b',
        onSelect: (_) {},
        onConfirm: noop,
      ),
    );
    expect(find.text('Glide Quiet'), findsOneWidget);
    expect(find.text('CONFIRM GLIDE QUIET'), findsOneWidget);
  });

  testWidgets('1b — driver assigned', (tester) async {
    await pumpCard(
      tester,
      DriverAssignedCard(
        status: 'Driver en route',
        name: 'Marcus Oyelaran',
        rating: '4.96',
        trips: '2,318',
        vehicle: 'Silver Toyota Prius',
        plate: 'LM72 KDR',
        onMessage: noop,
        onCall: noop,
        onCancel: noop,
      ),
    );
    expect(find.text('Marcus Oyelaran'), findsOneWidget);
    expect(find.text('LM72 KDR'), findsOneWidget);
  });

  testWidgets('1c — trip in progress', (tester) async {
    await pumpCard(
      tester,
      const TripProgressSheet(
        arriving: '6 min',
        remaining: '2.4 KM REMAINING',
        eta: 'ETA 09:41',
        progress: 0.62,
        from: "Queen's Quay",
        to: 'Aldgate E.',
        coordinates: '57.9097° N\n5.2107° W',
      ),
    );
    expect(find.text('6 min'), findsOneWidget);
  });

  testWidgets('1d — fare breakdown (open)', (tester) async {
    await pumpCard(
      tester,
      FareBreakdownCard(
        title: 'Fare — Plate III',
        date: '2026-07-21',
        total: '£18.40',
        lines: const [
          FareLine(label: 'BASE FARE', value: '£4.20'),
          FareLine(label: 'BOOKING FEE', value: '£1.18'),
        ],
        open: true,
        onToggle: noop,
      ),
    );
    expect(find.text('£18.40'), findsOneWidget);
    expect(find.text('HIDE BREAKDOWN ↑'), findsOneWidget);
    expect(find.text('£4.20'), findsOneWidget);
  });

  testWidgets('1e — rate & tip', (tester) async {
    await pumpCard(
      tester,
      RateAndTipCard(
        question: 'How was your ride with Marcus?',
        rating: 5,
        onRate: (_) {},
        tips: const ['None', '£1', '£2', '£5'],
        selectedTip: 1,
        onTip: (_) {},
      ),
    );
    expect(find.text('★'), findsNWidgets(5));
    expect(find.text('£2'), findsOneWidget);
  });

  testWidgets('1f — saved places', (tester) async {
    await pumpCard(
      tester,
      SavedPlacesCard(
        places: const [
          SavedPlace(
            tag: 'H',
            name: 'Home',
            address: "14 QUEEN'S QUAY, E1",
            distance: '0.4 KM',
          ),
          SavedPlace(tag: '+', name: 'Add a place', address: 'SAVED SHORTCUT'),
        ],
        onTap: (_) {},
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('0.4 KM'), findsOneWidget);
  });

  testWidgets('1g — payment method', (tester) async {
    await pumpCard(
      tester,
      const PaymentMethodCard(
        maskedNumber: '•••• •••• •••• 4172',
        holder: 'A. Vance',
        expiry: '09 / 29',
      ),
    );
    expect(find.text('•••• •••• •••• 4172'), findsOneWidget);
    expect(find.text('DEFAULT'), findsOneWidget);
  });

  testWidgets('1h — trip history', (tester) async {
    await pumpCard(
      tester,
      const TripHistoryCard(
        entries: [
          TripHistoryEntry(
            date: '21 JUL · 09:41',
            price: '£18.40',
            route: "Queen's Quay → Aldgate East",
            meta: 'GLIDE QUIET · 22 MIN · 4.96 ★',
          ),
        ],
      ),
    );
    expect(find.text("Queen's Quay → Aldgate East"), findsOneWidget);
  });

  testWidgets('1i — finding-driver skeleton', (tester) async {
    await pumpCard(tester, const FindingDriverSkeleton());
    expect(find.text('FINDING A DRIVER'), findsOneWidget);
    expect(find.text('SEARCHING 12 VEHICLES NEARBY'), findsOneWidget);
  });

  testWidgets('1j — surge notice', (tester) async {
    await pumpCard(
      tester,
      SurgeNoticeCard(
        message: 'Fares in this area are 1.6× until 21:30.',
        estimate: 'Estimated £18.40 → £29.44',
        onAccept: noop,
        onWait: noop,
      ),
    );
    expect(find.text('ACCEPT FARE'), findsOneWidget);
    expect(find.text('WAIT'), findsOneWidget);
  });
}
