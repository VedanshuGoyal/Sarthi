import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/multi_stop_trip.dart';
import '../domain/pickup_location.dart';
import '../domain/scheduling.dart' show tooSoonHint;
import '../ride_providers.dart';
import '../view_model/multi_stop_planner_view_model.dart';
import 'pickup_location_screen.dart';
import 'widgets/schedule_field.dart';
import 'widgets/stop_card.dart';
import 'widgets/ride_theme.dart';
import 'widgets/time_slot_picker.dart';

/// Step 3 of a Multi-Stop trip: write the driver's plan for the day.
///
/// Given the confirmed [start], the customer sets a start time and builds an
/// ordered list of stops — each with a location, a task in their own words,
/// and a leave-by deadline. On confirm the assembled [MultiStopTrip] is handed
/// back via [onConfirmed]. State lives in [multiStopPlannerViewModelProvider],
/// keyed on the start; this view renders it, owns the per-stop text
/// controllers, and drives the pickers.
class MultiStopPlannerScreen extends ConsumerStatefulWidget {
  const MultiStopPlannerScreen({
    super.key,
    required this.start,
    this.onConfirmed,
  });

  final PickupLocation start;

  /// Invoked with the assembled trip when the CTA is tapped. Defaults to
  /// popping the screen and returning the trip to the previous route.
  final void Function(BuildContext context, MultiStopTrip trip)? onConfirmed;

  @override
  ConsumerState<MultiStopPlannerScreen> createState() =>
      _MultiStopPlannerScreenState();
}

class _MultiStopPlannerScreenState
    extends ConsumerState<MultiStopPlannerScreen> {
  /// One text controller per stop, keyed by the draft's stable id so text
  /// follows its stop through reorders. Created lazily, disposed with us.
  final _taskControllers = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _taskControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _taskControllerFor(StopDraft stop) => _taskControllers
      .putIfAbsent(stop.id, () => TextEditingController(text: stop.task));

  Future<DateTime?> _pickDate(DateTime current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    return picked == null ? null : ScheduleField.withDate(current, picked);
  }

  /// [isAvailable] greys out the times it rejects (too-soon trip starts).
  Future<DateTime?> _pickTime(
    DateTime current, {
    bool Function(DateTime when)? isAvailable,
  }) async {
    final picked = await showTimeSlotPicker(
      context,
      initial: TimeOfDay.fromDateTime(current),
      isAvailable: isAvailable == null
          ? null
          : (slot) => isAvailable(ScheduleField.withTime(current, slot)),
    );
    return picked == null ? null : ScheduleField.withTime(current, picked);
  }

  Future<void> _pickStartDate(MultiStopPlannerViewModel vm) async {
    final when = await _pickDate(vm.scheduledAt);
    if (when != null) vm.setScheduledAt(when);
  }

  Future<void> _pickStartTime(MultiStopPlannerViewModel vm) async {
    final when = await _pickTime(
      vm.scheduledAt,
      isAvailable: vm.isStartAvailable,
    );
    if (when != null) vm.setScheduledAt(when);
  }

  /// A stop with no deadline yet starts its pickers from the trip's start
  /// time, so a time-only pick lands on the right day.
  Future<void> _pickStopDate(
    MultiStopPlannerViewModel vm,
    StopDraft stop,
  ) async {
    final when = await _pickDate(stop.departBy ?? vm.scheduledAt);
    if (when != null) vm.setStopDepartBy(stop.id, when);
  }

  Future<void> _pickStopTime(
    MultiStopPlannerViewModel vm,
    StopDraft stop,
  ) async {
    final when = await _pickTime(stop.departBy ?? vm.scheduledAt);
    if (when != null) vm.setStopDepartBy(stop.id, when);
  }

  Future<void> _pickStopLocation(
    MultiStopPlannerViewModel vm,
    StopDraft stop,
  ) async {
    final location = await Navigator.of(context).push<PickupLocation>(
      MaterialPageRoute(
        builder: (_) => const PickupLocationScreen(
          title: 'Set stop location',
          fieldLabel: 'Stop location',
        ),
      ),
    );
    if (location != null) vm.setStopLocation(stop.id, location);
  }

  void _confirm(MultiStopTrip trip) {
    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) return onConfirmed(context, trip);
    Navigator.of(context).pop(trip);
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(multiStopPlannerViewModelProvider(widget.start));
    final theme = Theme.of(context);

    return Theme(
      data: rideSurfaceTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Plan your trip')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        _StartSummary(address: vm.start.address),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'When do we start?',
                          subtitle:
                              'The driver meets you at the starting point.',
                          child: ScheduleField(
                            scheduledAt: vm.scheduledAt,
                            onTapDate: () => _pickStartDate(vm),
                            onTapTime: () => _pickStartTime(vm),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'Stops',
                          subtitle:
                              'List each errand in order — where to go, what to '
                              'do there, and when to move on.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, stop) in vm.stops.indexed) ...[
                                StopCard(
                                  key: ValueKey(stop.id),
                                  index: i + 1,
                                  address: stop.location?.address,
                                  taskController: _taskControllerFor(stop),
                                  departBy: stop.departBy,
                                  timeError: vm.timeErrorFor(stop.id),
                                  canRemove: vm.canRemoveStop,
                                  canMoveUp: i > 0,
                                  canMoveDown: i < vm.stops.length - 1,
                                  onPickLocation: () =>
                                      _pickStopLocation(vm, stop),
                                  onTaskChanged: (task) =>
                                      vm.setStopTask(stop.id, task),
                                  onTapDate: () => _pickStopDate(vm, stop),
                                  onTapTime: () => _pickStopTime(vm, stop),
                                  onRemove: () => vm.removeStop(stop.id),
                                  onMoveUp: () => vm.moveStopUp(stop.id),
                                  onMoveDown: () => vm.moveStopDown(stop.id),
                                ),
                                const SizedBox(height: 12),
                              ],
                              OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.add_location_alt_outlined,
                                ),
                                label: Text(
                                  vm.canAddStop
                                      ? 'Add stop'
                                      : 'Up to ${MultiStopPlannerViewModel.maxStops} stops',
                                ),
                                onPressed: vm.canAddStop ? vm.addStop : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SkylineActionBar(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _planSummaryText(context, vm, theme),
                        ),
                        SarthiPrimaryButton(
                          label: 'Confirm trip',
                          onPressed: vm.canConfirm
                              ? () => _confirm(vm.trip!)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The line above the CTA: the plan's shape once confirmable, or what's
  /// still missing while it isn't.
  Widget _planSummaryText(
    BuildContext context,
    MultiStopPlannerViewModel vm,
    ThemeData theme,
  ) {
    final String text;
    if (vm.canConfirm) {
      final l10n = MaterialLocalizations.of(context);
      final endsAt = vm.endsAt!;
      final count = vm.stops.length;
      text =
          '$count ${count == 1 ? 'stop' : 'stops'} · wraps up by '
          '${l10n.formatMediumDate(endsAt)}, '
          '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(endsAt))}';
    } else if (vm.isTooSoon) {
      text = tooSoonHint;
    } else {
      text =
          'Give every stop a location, a task, and a leave-by time to '
          'continue.';
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A compact, read-only banner echoing the starting point chosen previously.
class _StartSummary extends StatelessWidget {
  const _StartSummary({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) =>
      SkylinePlaceSummary(label: 'Starting point', address: address);
}

/// A titled section: a heading (with optional [subtitle]) above its [child].
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SkylineSection(title: title, subtitle: subtitle, child: child);
}
