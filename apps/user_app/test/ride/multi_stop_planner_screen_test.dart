import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/multi_stop_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/multi_stop_planner_screen.dart';
import 'package:user_app/features/ride/view/widgets/stop_card.dart';
import 'package:user_app/features/ride/view_model/multi_stop_planner_view_model.dart';

const _start = PickupLocation(
  address: 'MG Road, Bengaluru',
  point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
);

const _pharmacy = PickupLocation(
  address: 'Apollo Pharmacy, Indiranagar',
  point: GeoPoint(latitude: 12.9719, longitude: 77.6412),
);

const _office = PickupLocation(
  address: 'Passport Seva Kendra, Lalbagh Road',
  point: GeoPoint(latitude: 12.9581, longitude: 77.5850),
);

final _nineAm = DateTime(2026, 7, 18, 9);

/// Pumps the planner with the view model seeded to [stops] (or the default
/// single blank stop) on a surface tall enough to lay out every card at once.
Future<void> _pump(
  WidgetTester tester, {
  List<StopDraft>? stops,
  ValueChanged<MultiStopTrip>? onOk,
}) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        multiStopPlannerViewModelProvider.overrideWith(
          (ref, start) => MultiStopPlannerViewModel(
            start: start,
            initialScheduledAt: _nineAm,
            initialStops: stops,
          ),
        ),
      ],
      child: MaterialApp(
        home: MultiStopPlannerScreen(
          start: _start,
          onConfirmed: onOk == null ? null : (_, trip) => onOk(trip),
        ),
      ),
    ),
  );
}

/// Two fully written stops in a valid order — a confirmable plan.
List<StopDraft> _readyStops() => [
  StopDraft(
    id: 0,
    location: _pharmacy,
    task: 'Collect the refill',
    departBy: DateTime(2026, 7, 18, 10, 30),
  ),
  StopDraft(
    id: 1,
    location: _office,
    task: 'Drop the forms at counter 4',
    departBy: DateTime(2026, 7, 18, 12, 15),
  ),
];

void main() {
  testWidgets('starts with the echo, one blank stop, and confirm disabled', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('MG Road, Bengaluru'), findsOneWidget); // start echo
    expect(find.text('Stop 1'), findsOneWidget);
    expect(find.text('Choose location'), findsOneWidget);
    expect(find.text('Select date'), findsOneWidget); // no leave-by yet
    expect(find.text('Add stop'), findsOneWidget);
    expect(
      find.text(
        'Give every stop a location, a task, and a leave-by time to '
        'continue.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('add stop appends a card; delete removes it again', (
    tester,
  ) async {
    await _pump(tester);

    // The lone stop can't be deleted.
    final delete = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(tester.widget<IconButton>(delete).onPressed, isNull);

    await tester.tap(find.text('Add stop'));
    await tester.pump();
    expect(find.text('Stop 2'), findsOneWidget);

    await tester.tap(delete.last);
    await tester.pump();
    expect(find.text('Stop 2'), findsNothing);
  });

  testWidgets('the arrows reorder stops, and their text goes along', (
    tester,
  ) async {
    await _pump(tester, stops: _readyStops());

    final cards = find.byType(StopCard);
    Finder inFirstCard(String text) =>
        find.descendant(of: cards.first, matching: find.text(text));

    expect(inFirstCard(_pharmacy.address), findsOneWidget);

    await tester.tap(
      find
          .descendant(
            of: cards.first,
            matching: find.widgetWithIcon(IconButton, Icons.arrow_downward),
          )
          .first,
    );
    await tester.pump();

    // The whole stop — place and task — now sits second; the office leads.
    expect(inFirstCard(_office.address), findsOneWidget);
    expect(inFirstCard('Drop the forms at counter 4'), findsOneWidget);
  });

  testWidgets('a broken timeline is flagged on the offending stop', (
    tester,
  ) async {
    final stops = _readyStops();
    // Stop 2 now leaves before stop 1 does.
    stops[1] = StopDraft(
      id: 1,
      location: _office,
      task: 'Drop the forms at counter 4',
      departBy: DateTime(2026, 7, 18, 10),
    );
    await _pump(tester, stops: stops);

    expect(find.text('Leave-by must be after stop 1.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('typing the last missing task unlocks confirm', (tester) async {
    final stops = _readyStops();
    stops[1] = StopDraft(
      id: 1,
      location: _office,
      task: '', // everything set but the task
      departBy: DateTime(2026, 7, 18, 12, 15),
    );
    await _pump(tester, stops: stops);

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byType(TextField).last,
      'Drop the forms at counter 4',
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('confirming returns the assembled trip', (tester) async {
    MultiStopTrip? received;
    await _pump(tester, stops: _readyStops(), onOk: (t) => received = t);

    expect(find.textContaining('2 stops · wraps up by'), findsOneWidget);

    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Confirm trip'));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.start.address, 'MG Road, Bengaluru');
    expect(received!.stops.length, 2);
    expect(received!.stops[0].task, 'Collect the refill');
    expect(received!.endsAt, DateTime(2026, 7, 18, 12, 15));
  });
}
