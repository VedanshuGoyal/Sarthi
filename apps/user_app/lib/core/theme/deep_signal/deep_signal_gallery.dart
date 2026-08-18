import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'deep_signal.dart';

/// A living catalogue of the Deep Signal card set, wired with real interactive
/// state. It renders in whatever mode is active, so flipping the app-bar
/// [ThemeModeToggle] shows every card cross-fade between light and dark.
///
/// Handy as a design reference and as a manual smoke-test of the theme. Push it
/// with `Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
/// const DeepSignalGalleryScreen()))`.
class DeepSignalGalleryScreen extends ConsumerStatefulWidget {
  const DeepSignalGalleryScreen({super.key});

  @override
  ConsumerState<DeepSignalGalleryScreen> createState() =>
      _DeepSignalGalleryScreenState();
}

class _DeepSignalGalleryScreenState
    extends ConsumerState<DeepSignalGalleryScreen> {
  String _ride = 'quiet';
  bool _fareOpen = true;
  int _rating = 5;
  int _tip = 1;

  static const _rides = [
    RideClassOption(
      id: 'glide',
      name: 'Glide',
      meta: '4 SEATS · 3 MIN',
      price: '£12.80',
      note: 'STANDARD',
    ),
    RideClassOption(
      id: 'quiet',
      name: 'Glide Quiet',
      meta: '4 SEATS · 5 MIN',
      price: '£18.40',
      note: 'NO SMALL TALK',
    ),
    RideClassOption(
      id: 'xl',
      name: 'Ledger XL',
      meta: '6 SEATS · 9 MIN',
      price: '£26.10',
      note: 'LARGE',
    ),
  ];

  static const _fareLines = [
    FareLine(label: 'BASE FARE', value: '£4.20'),
    FareLine(label: 'DISTANCE · 8.1 KM', value: '£9.72'),
    FareLine(label: 'TIME · 22 MIN', value: '£3.30'),
    FareLine(label: 'BOOKING FEE', value: '£1.18'),
    FareLine(label: 'TIP', value: '£0.00'),
  ];

  static const _places = [
    SavedPlace(
      tag: 'H',
      name: 'Home',
      address: "14 QUEEN'S QUAY, E1",
      distance: '0.4 KM',
    ),
    SavedPlace(
      tag: 'W',
      name: 'Studio',
      address: '3 CHARLOTTE RD, EC2',
      distance: '5.1 KM',
    ),
    SavedPlace(tag: '+', name: 'Add a place', address: 'SAVED SHORTCUT'),
  ];

  static const _history = [
    TripHistoryEntry(
      date: '21 JUL · 09:41',
      price: '£18.40',
      route: "Queen's Quay → Aldgate East",
      meta: 'GLIDE QUIET · 22 MIN · 4.96 ★',
    ),
    TripHistoryEntry(
      date: '18 JUL · 19:02',
      price: '£26.10',
      route: 'Studio → St Pancras Intl',
      meta: 'LEDGER XL · 34 MIN · 5.00 ★',
    ),
    TripHistoryEntry(
      date: '16 JUL · 07:15',
      price: '£12.80',
      route: 'Home → Shoreditch High St',
      meta: 'GLIDE · 11 MIN · 4.80 ★',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final mode = ref.watch(themeModeProvider);

    final cards = <Widget>[
      DeepSignalRideClassPicker(
        options: _rides,
        selectedId: _ride,
        onSelect: (id) => setState(() => _ride = id),
        onConfirm: () {},
        width: double.infinity,
      ),
      const DeepSignalDriverAssignedCard(
        status: 'Driver en route',
        name: 'Marcus Oyelaran',
        rating: '4.96',
        trips: '2,318',
        vehicle: 'Silver Toyota Prius',
        plate: 'LM72 KDR',
        onMessage: _noop,
        onCall: _noop,
        onCancel: _noop,
        width: double.infinity,
      ),
      const DeepSignalTripProgressSheet(
        arriving: '6 min',
        remaining: '2.4 KM REMAINING',
        eta: 'ETA 09:41',
        progress: 0.62,
        from: "Queen's Quay",
        to: 'Aldgate E.',
        coordinates: '57.9097° N\n5.2107° W',
        width: double.infinity,
      ),
      DeepSignalFareBreakdownCard(
        title: 'Fare — Plate III',
        date: '2026-07-21',
        total: '£18.40',
        lines: _fareLines,
        open: _fareOpen,
        onToggle: () => setState(() => _fareOpen = !_fareOpen),
        width: double.infinity,
      ),
      DeepSignalRateAndTipCard(
        question: 'How was your ride with Marcus?',
        rating: _rating,
        onRate: (n) => setState(() => _rating = n),
        tips: const ['None', '£1', '£2', '£5'],
        selectedTip: _tip,
        onTip: (i) => setState(() => _tip = i),
        width: double.infinity,
      ),
      DeepSignalSavedPlacesCard(
        places: _places,
        onTap: (_) {},
        width: double.infinity,
      ),
      const DeepSignalPaymentMethodCard(
        maskedNumber: '•••• •••• •••• 4172',
        holder: 'A. Vance',
        expiry: '09 / 29',
        width: double.infinity,
      ),
      const DeepSignalTripHistoryCard(
        entries: _history,
        width: double.infinity,
      ),
      const DeepSignalFindingDriverSkeleton(width: double.infinity),
      DeepSignalSurgeNoticeCard(
        message: 'Fares in this area are 1.6× until 21:30.',
        estimate: 'Estimated £18.40 → £29.44',
        onAccept: () {},
        onWait: () {},
        width: double.infinity,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deep Signal'),
        actions: const [ThemeModeToggle(), SizedBox(width: 4)],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // One column on phones, more as width allows; each column caps at
            // the design's 390 card width.
            const gap = DeepSignalTokens.s22;
            final columns = (constraints.maxWidth / 420).floor().clamp(1, 3);
            final cardWidth =
                (constraints.maxWidth - 32 - gap * (columns - 1)) / columns;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 16),
                    child: Text(
                      'RIDE CARDS · ${themeModeLabel(mode)} · '
                      '${t.isDark ? 'DARK' : 'LIGHT'}',
                      style: t.mono(color: t.faint, trackingEm: 0.2),
                    ),
                  ),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final card in cards)
                        SizedBox(width: cardWidth, child: card),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

void _noop() {}
