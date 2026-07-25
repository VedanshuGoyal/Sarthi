import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/scheduling.dart' as scheduling;
import 'package:user_app/features/ride/view/widgets/time_slot_picker.dart';

void main() {
  group('snapToQuarterHour', () {
    test('rounds to the nearest quarter hour', () {
      check(
        scheduling.snapToQuarterHour(DateTime(2026, 7, 20, 9, 7)),
      ).equals(DateTime(2026, 7, 20, 9, 0));
      check(
        scheduling.snapToQuarterHour(DateTime(2026, 7, 20, 9, 8)),
      ).equals(DateTime(2026, 7, 20, 9, 15));
      check(
        scheduling.snapToQuarterHour(DateTime(2026, 7, 20, 9, 30)),
      ).equals(DateTime(2026, 7, 20, 9, 30));
    });

    test('carries :53+ into the next hour and day', () {
      check(
        scheduling.snapToQuarterHour(DateTime(2026, 7, 20, 9, 55)),
      ).equals(DateTime(2026, 7, 20, 10, 0));
      check(
        scheduling.snapToQuarterHour(DateTime(2026, 7, 20, 23, 55)),
      ).equals(DateTime(2026, 7, 21, 0, 0));
    });
  });

  group('TimeSlotPicker slots', () {
    test('covers the day in 15-minute steps', () {
      check(TimeSlotPicker.slotCount).equals(96);
      check(
        TimeSlotPicker.slotAt(0),
      ).equals(const TimeOfDay(hour: 0, minute: 0));
      check(
        TimeSlotPicker.slotAt(37),
      ).equals(const TimeOfDay(hour: 9, minute: 15));
      check(
        TimeSlotPicker.slotAt(95),
      ).equals(const TimeOfDay(hour: 23, minute: 45));
    });

    test('nearestSlotIndex snaps off-grid times onto the grid', () {
      check(
        TimeSlotPicker.nearestSlotIndex(const TimeOfDay(hour: 9, minute: 15)),
      ).equals(37);
      check(
        TimeSlotPicker.nearestSlotIndex(const TimeOfDay(hour: 9, minute: 20)),
      ).equals(37);
      // 23:53+ wraps onto midnight rather than past the end of the list.
      check(
        TimeSlotPicker.nearestSlotIndex(const TimeOfDay(hour: 23, minute: 55)),
      ).equals(0);
    });
  });

  testWidgets('lists only quarter-hour times and emits the tapped slot', (
    tester,
  ) async {
    TimeOfDay? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimeSlotPicker(
            selected: const TimeOfDay(hour: 9, minute: 15),
            onSelected: (slot) => selected = slot,
          ),
        ),
      ),
    );

    // The list opens around the selection: the slot itself plus its
    // quarter-hour neighbours are built; an off-grid time never appears.
    expect(find.text('9:15 AM'), findsOneWidget);
    expect(find.text('9:30 AM'), findsOneWidget);
    expect(find.text('9:20 AM'), findsNothing);

    await tester.tap(find.text('9:30 AM'));
    check(selected).equals(const TimeOfDay(hour: 9, minute: 30));
  });

  testWidgets('showTimeSlotPicker resolves with the chosen slot', (
    tester,
  ) async {
    TimeOfDay? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showTimeSlotPicker(
                  context,
                  initial: const TimeOfDay(hour: 12, minute: 0),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Trips start every 15 minutes.'), findsOneWidget);

    await tester.tap(find.text('12:15 PM'));
    await tester.pumpAndSettle();

    check(result).equals(const TimeOfDay(hour: 12, minute: 15));
    expect(find.text('Trips start every 15 minutes.'), findsNothing);
  });
}
