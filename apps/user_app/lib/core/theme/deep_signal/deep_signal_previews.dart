import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'deep_signal.dart';

/// Registers both Deep Signal modes so previews can render either.
PreviewThemeData deepSignalPreviewTheme() => PreviewThemeData(
  materialLight: DeepSignalTheme.light(),
  materialDark: DeepSignalTheme.dark(),
);

/// Frames a single card on the mode's canvas, as it sits in the app.
Widget _stage(DeepSignalTokens tokens, Widget card) => Theme(
  data: DeepSignalTheme.of(tokens.brightness),
  child: ColoredBox(
    color: tokens.canvas,
    child: Padding(
      padding: const EdgeInsets.all(DeepSignalTokens.s22),
      child: Align(alignment: Alignment.topCenter, child: card),
    ),
  ),
);

/// Renders [build] in light **and** dark side by side, so a preview shows both
/// modes and their parity at a glance. [build] is called once per mode so
/// stateful demos stay independent.
Widget _dual(Widget Function() build) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(child: _stage(DeepSignalTokens.light, build())),
    Expanded(child: _stage(DeepSignalTokens.dark, build())),
  ],
);

// --- Sample data -----------------------------------------------------------

const _rides = [
  RideClassOption(id: 'glide', name: 'Glide', meta: '4 SEATS · 3 MIN', price: '£12.80', note: 'STANDARD'),
  RideClassOption(id: 'quiet', name: 'Glide Quiet', meta: '4 SEATS · 5 MIN', price: '£18.40', note: 'NO SMALL TALK'),
  RideClassOption(id: 'xl', name: 'Ledger XL', meta: '6 SEATS · 9 MIN', price: '£26.10', note: 'LARGE'),
];

const _fareLines = [
  FareLine(label: 'BASE FARE', value: '£4.20'),
  FareLine(label: 'DISTANCE · 8.1 KM', value: '£9.72'),
  FareLine(label: 'TIME · 22 MIN', value: '£3.30'),
  FareLine(label: 'BOOKING FEE', value: '£1.18'),
  FareLine(label: 'TIP', value: '£0.00'),
];

const _places = [
  SavedPlace(tag: 'H', name: 'Home', address: "14 QUEEN'S QUAY, E1", distance: '0.4 KM'),
  SavedPlace(tag: 'W', name: 'Studio', address: '3 CHARLOTTE RD, EC2', distance: '5.1 KM'),
  SavedPlace(tag: '+', name: 'Add a place', address: 'SAVED SHORTCUT'),
];

const _history = [
  TripHistoryEntry(date: '21 JUL · 09:41', price: '£18.40', route: "Queen's Quay → Aldgate East", meta: 'GLIDE QUIET · 22 MIN · 4.96 ★'),
  TripHistoryEntry(date: '18 JUL · 19:02', price: '£26.10', route: 'Studio → St Pancras Intl', meta: 'LEDGER XL · 34 MIN · 5.00 ★'),
  TripHistoryEntry(date: '16 JUL · 07:15', price: '£12.80', route: 'Home → Shoreditch High St', meta: 'GLIDE · 11 MIN · 4.80 ★'),
];

void _noop() {}

// --- a — Ride class picker -------------------------------------------------

@Preview(name: 'a · Ride class picker', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget rideClassPickerPreview() => _dual(() => const _RideDemo());

class _RideDemo extends StatefulWidget {
  const _RideDemo();
  @override
  State<_RideDemo> createState() => _RideDemoState();
}

class _RideDemoState extends State<_RideDemo> {
  String _selected = 'quiet';
  @override
  Widget build(BuildContext context) => DeepSignalRideClassPicker(
    options: _rides,
    selectedId: _selected,
    onSelect: (id) => setState(() => _selected = id),
    onConfirm: _noop,
  );
}

// --- b — Driver assigned ---------------------------------------------------

@Preview(name: 'b · Driver assigned', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget driverAssignedPreview() => _dual(
  () => const DeepSignalDriverAssignedCard(
    status: 'Driver en route',
    name: 'Marcus Oyelaran',
    rating: '4.96',
    trips: '2,318',
    vehicle: 'Silver Toyota Prius',
    plate: 'LM72 KDR',
    onMessage: _noop,
    onCall: _noop,
    onCancel: _noop,
  ),
);

// --- c — Trip in progress --------------------------------------------------

@Preview(name: 'c · Trip in progress', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget tripProgressPreview() => _dual(
  () => const DeepSignalTripProgressSheet(
    arriving: '6 min',
    remaining: '2.4 KM REMAINING',
    eta: 'ETA 09:41',
    progress: 0.62,
    from: "Queen's Quay",
    to: 'Aldgate E.',
    coordinates: '57.9097° N\n5.2107° W',
  ),
);

// --- d — Fare breakdown ----------------------------------------------------

@Preview(name: 'd · Fare breakdown', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget fareBreakdownPreview() => _dual(() => const _FareDemo());

class _FareDemo extends StatefulWidget {
  const _FareDemo();
  @override
  State<_FareDemo> createState() => _FareDemoState();
}

class _FareDemoState extends State<_FareDemo> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => DeepSignalFareBreakdownCard(
    title: 'Fare — Plate III',
    date: '2026-07-21',
    total: '£18.40',
    lines: _fareLines,
    open: _open,
    onToggle: () => setState(() => _open = !_open),
  );
}

// --- e — Rate & tip --------------------------------------------------------

@Preview(name: 'e · Rate & tip', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget rateAndTipPreview() => _dual(() => const _RateDemo());

class _RateDemo extends StatefulWidget {
  const _RateDemo();
  @override
  State<_RateDemo> createState() => _RateDemoState();
}

class _RateDemoState extends State<_RateDemo> {
  int _rating = 5;
  int _tip = 1;
  @override
  Widget build(BuildContext context) => DeepSignalRateAndTipCard(
    question: 'How was your ride with Marcus?',
    rating: _rating,
    onRate: (n) => setState(() => _rating = n),
    tips: const ['None', '£1', '£2', '£5'],
    selectedTip: _tip,
    onTip: (i) => setState(() => _tip = i),
  );
}

// --- f — Saved places ------------------------------------------------------

@Preview(name: 'f · Saved places', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget savedPlacesPreview() =>
    _dual(() => DeepSignalSavedPlacesCard(places: _places, onTap: (_) {}));

// --- g — Payment method ----------------------------------------------------

@Preview(name: 'g · Payment method', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget paymentMethodPreview() => _dual(
  () => const DeepSignalPaymentMethodCard(
    maskedNumber: '•••• •••• •••• 4172',
    holder: 'A. Vance',
    expiry: '09 / 29',
  ),
);

// --- h — Trip history ------------------------------------------------------

@Preview(name: 'h · Trip history', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget tripHistoryPreview() =>
    _dual(() => const DeepSignalTripHistoryCard(entries: _history));

// --- i — Loading skeleton --------------------------------------------------

@Preview(name: 'i · Loading skeleton', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget findingDriverPreview() =>
    _dual(() => const DeepSignalFindingDriverSkeleton());

// --- j — Surge notice ------------------------------------------------------

@Preview(name: 'j · Surge notice', group: 'Deep Signal', theme: deepSignalPreviewTheme)
Widget surgeNoticePreview() => _dual(
  () => DeepSignalSurgeNoticeCard(
    message: 'Fares in this area are 1.6× until 21:30.',
    estimate: 'Estimated £18.40 → £29.44',
    onAccept: _noop,
    onWait: _noop,
  ),
);
