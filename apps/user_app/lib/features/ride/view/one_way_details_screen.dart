import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/one_way_trip.dart';
import '../domain/pickup_location.dart';
import '../ride_providers.dart';
import '../view_model/one_way_details_view_model.dart';
import 'one_way_review_screen.dart';
import 'widgets/add_car_sheet.dart';
import 'widgets/car_selector_field.dart';
import 'widgets/route_map.dart';
import 'widgets/route_summary.dart';
import 'widgets/schedule_field.dart';
import 'widgets/time_slot_picker.dart';
import 'widgets/ride_theme.dart';

/// The One-Way "trip details" step: when to go and which car.
///
/// Given the confirmed [start] and [destination], the customer picks a start
/// date/time and one of their saved cars (adding a car inline when needed) —
/// with no drive-time lookups while
/// they change their mind. Continuing pushes [OneWayReviewScreen], which
/// fetches the estimate once for the settled departure and owns the final
/// confirmation; the confirmed [OneWayTrip] is then handed back via
/// [onConfirmed]. State lives in [oneWayDetailsViewModelProvider], keyed on
/// the route; this view only renders it and drives the pickers.
class OneWayDetailsScreen extends ConsumerWidget {
  const OneWayDetailsScreen({
    super.key,
    required this.start,
    required this.destination,
    this.onConfirmed,
  });

  final PickupLocation start;
  final PickupLocation destination;

  /// Invoked with the assembled trip once the review step confirms it.
  /// Defaults to popping this screen and returning the trip to the previous
  /// route.
  final void Function(BuildContext context, OneWayTrip trip)? onConfirmed;

  Future<void> _pickDate(
    BuildContext context,
    OneWayDetailsViewModel vm,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.scheduledAt,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) {
      vm.setScheduledAt(ScheduleField.withDate(vm.scheduledAt, picked));
    }
  }

  Future<void> _pickTime(
    BuildContext context,
    OneWayDetailsViewModel vm,
  ) async {
    final picked = await showTimeSlotPicker(
      context,
      initial: TimeOfDay.fromDateTime(vm.scheduledAt),
    );
    if (picked != null) {
      vm.setScheduledAt(ScheduleField.withTime(vm.scheduledAt, picked));
    }
  }

  Future<void> _continue(BuildContext context, OneWayDraft draft) async {
    final trip = await Navigator.of(context).push<OneWayTrip>(
      MaterialPageRoute(builder: (_) => OneWayReviewScreen(draft: draft)),
    );
    if (trip == null || !context.mounted) return;
    if (onConfirmed != null) return onConfirmed!(context, trip);
    Navigator.of(context).pop(trip);
  }

  /// Opens the add-car sheet and selects whatever car it saved.
  Future<void> _addCar(BuildContext context, WidgetRef ref) async {
    final car = await showAddCarSheet(context);
    if (car == null || !context.mounted) return;
    ref
        .read(
          oneWayDetailsViewModelProvider((
            start: start,
            destination: destination,
          )),
        )
        .selectCar(car);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(
      oneWayDetailsViewModelProvider((start: start, destination: destination)),
    );
    final savedCars = ref.watch(savedCarsViewModelProvider);
    final theme = Theme.of(context);

    return Theme(
      data: rideSurfaceTheme(context),
      child: Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      RouteSummary(
                        startAddress: vm.start.address,
                        destinationAddress: vm.destination.address,
                      ),
                      const SizedBox(height: 12),
                      RouteMap(
                        start: vm.start.point,
                        destination: vm.destination.point,
                        startLabel: vm.start.address,
                        destinationLabel: vm.destination.address,
                      ),
                      const SizedBox(height: 24),
                      _Section(
                        title: 'When?',
                        subtitle: 'Pick a start date and time.',
                        child: ScheduleField(
                          scheduledAt: vm.scheduledAt,
                          onTapDate: () => _pickDate(context, vm),
                          onTapTime: () => _pickTime(context, vm),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Which car?',
                        subtitle: 'The driver drives your car — pick one.',
                        child: CarSelectorField(
                          cars: savedCars.cars,
                          selected: vm.car,
                          isLoading: savedCars.isLoading,
                          loadFailed: savedCars.loadFailed,
                          onSelected: vm.selectCar,
                          onRetry: savedCars.load,
                          onAddCar: () => _addCar(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!vm.canContinue)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Choose your car to continue.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      SarthiPrimaryButton(
                        label: 'Continue',
                        onPressed: vm.canContinue
                            ? () => _continue(context, vm.draft!)
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
}

/// A titled section: a heading (with optional [subtitle]) above its [child].
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
