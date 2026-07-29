import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'vast_quiet.dart';

/// Applies the Vast Quiet [ThemeData] to every card preview so Material bits
/// (buttons, dividers) render in the design language.
PreviewThemeData vastQuietPreviewTheme() =>
    PreviewThemeData(materialLight: vastQuietTheme());

/// Frames a fixed-width card on the paper page, as it sits in the app.
Widget _stage(Widget card) => ColoredBox(
  color: VastQuiet.paper,
  child: Padding(
    padding: const EdgeInsets.all(VastQuiet.s34),
    child: Align(alignment: Alignment.topCenter, child: card),
  ),
);

// --- Sample data (mirrors the design doc's DCLogic) ------------------------

const _rides = [
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

const _fareLines = [
  FareLine(label: 'BASE FARE', value: '£4.20'),
  FareLine(label: 'DISTANCE · 8.1 KM', value: '£9.72'),
  FareLine(label: 'TIME · 22 MIN', value: '£3.30'),
  FareLine(label: 'BOOKING FEE', value: '£1.18'),
  FareLine(label: 'TIP', value: '£0.00'),
];

const _places = [
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

const _history = [
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

void _noop() {}
void _noopStr(Object? _) {}

// --- 1a — Ride class picker (interactive selection) ------------------------

@Preview(name: '1a · Ride class picker', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget rideClassPickerPreview() => _stage(const _RideClassPickerDemo());

class _RideClassPickerDemo extends StatefulWidget {
  const _RideClassPickerDemo();

  @override
  State<_RideClassPickerDemo> createState() => _RideClassPickerDemoState();
}

class _RideClassPickerDemoState extends State<_RideClassPickerDemo> {
  String _selected = 'quiet';

  @override
  Widget build(BuildContext context) => RideClassPicker(
    options: _rides,
    selectedId: _selected,
    onSelect: (id) => setState(() => _selected = id),
    onConfirm: _noop,
  );
}

// --- 1b — Driver assigned --------------------------------------------------

@Preview(name: '1b · Driver assigned', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget driverAssignedPreview() => _stage(
  DriverAssignedCard(
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

// --- 1c — Trip in progress -------------------------------------------------

@Preview(name: '1c · Trip in progress', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget tripProgressPreview() => _stage(
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

// --- 1d — Fare breakdown (interactive toggle) ------------------------------

@Preview(name: '1d · Fare breakdown', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget fareBreakdownPreview() => _stage(const _FareBreakdownDemo());

class _FareBreakdownDemo extends StatefulWidget {
  const _FareBreakdownDemo();

  @override
  State<_FareBreakdownDemo> createState() => _FareBreakdownDemoState();
}

class _FareBreakdownDemoState extends State<_FareBreakdownDemo> {
  bool _open = true;

  @override
  Widget build(BuildContext context) => FareBreakdownCard(
    title: 'Fare — Plate III',
    date: '2026-07-21',
    total: '£18.40',
    lines: _fareLines,
    open: _open,
    onToggle: () => setState(() => _open = !_open),
  );
}

// --- 1e — Rate & tip (interactive) -----------------------------------------

@Preview(name: '1e · Rate & tip', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget rateAndTipPreview() => _stage(const _RateAndTipDemo());

class _RateAndTipDemo extends StatefulWidget {
  const _RateAndTipDemo();

  @override
  State<_RateAndTipDemo> createState() => _RateAndTipDemoState();
}

class _RateAndTipDemoState extends State<_RateAndTipDemo> {
  int _rating = 5;
  int _tip = 1;

  @override
  Widget build(BuildContext context) => RateAndTipCard(
    question: 'How was your ride with Marcus?',
    rating: _rating,
    onRate: (n) => setState(() => _rating = n),
    tips: const ['None', '£1', '£2', '£5'],
    selectedTip: _tip,
    onTip: (i) => setState(() => _tip = i),
  );
}

// --- 1f — Saved places -----------------------------------------------------

@Preview(name: '1f · Saved places', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget savedPlacesPreview() =>
    _stage(SavedPlacesCard(places: _places, onTap: _noopStr));

// --- 1g — Payment method ---------------------------------------------------

@Preview(name: '1g · Payment method', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget paymentMethodPreview() => _stage(
  const PaymentMethodCard(
    maskedNumber: '•••• •••• •••• 4172',
    holder: 'A. Vance',
    expiry: '09 / 29',
  ),
);

// --- 1h — Trip history -----------------------------------------------------

@Preview(name: '1h · Trip history', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget tripHistoryPreview() => _stage(const TripHistoryCard(entries: _history));

// --- 1i — Loading skeleton -------------------------------------------------

@Preview(name: '1i · Loading skeleton', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget findingDriverPreview() => _stage(const FindingDriverSkeleton());

// --- 1j — Surge / unavailable ----------------------------------------------

@Preview(name: '1j · Surge notice', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget surgeNoticePreview() => _stage(
  SurgeNoticeCard(
    message: 'Fares in this area are 1.6× until 21:30.',
    estimate: 'Estimated £18.40 → £29.44',
    onAccept: _noop,
    onWait: _noop,
  ),
);

// --- Entry backdrop --------------------------------------------------------
// The landing-screen scene: alpenglow peaks over a sea of cloud, fading to
// paper. Framed as the header band it sits in behind the trip chooser.

@Preview(name: 'Entry backdrop', group: 'Vast Quiet', theme: vastQuietPreviewTheme)
Widget entryBackdropPreview() => const ColoredBox(
  color: VastQuiet.paper,
  child: SizedBox(
    height: 320,
    width: double.infinity,
    child: VastQuietBackdrop(),
  ),
);
