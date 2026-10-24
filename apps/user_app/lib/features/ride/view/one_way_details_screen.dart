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
        // The Continue bar is a fixed-height sibling below the map/sheet
        // area, not stacked on top of it — so the draggable sheet's travel
        // range (0%-100% of the Expanded region) never runs underneath it
        // and collapsing all the way down never hides the drag handle.
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RouteMap(
                      start: vm.start.point,
                      destination: vm.destination.point,
                      startLabel: vm.start.address,
                      destinationLabel: vm.destination.address,
                      fullScreen: true,
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                  // Drag up to reveal "When?"/"Which car?", drag down to
                  // collapse back to a peek so more of the route map shows.
                  DraggableScrollableSheet(
                    initialChildSize: 0.6,
                    minChildSize: 0.16,
                    maxChildSize: 1,
                    builder: (context, scrollController) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(Skyline.radiusXl),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                16,
                              ),
                              children: [
                                Center(
                                  child: Container(
                                    width: 36,
                                    height: 4,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                // The route in words — the map above is a
                                // preview and may be unavailable.
                                RouteSummary(
                                  startAddress: vm.start.address,
                                  destinationAddress: vm.destination.address,
                                ),
                                const SizedBox(height: 16),
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
                                  subtitle:
                                      'The driver drives your car — pick one.',
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
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Always below the Expanded map/sheet area — never covered by
            // the sheet at any drag position, so it's always reachable.
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                  ),
                ),
              ),
            ),
          ],
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
  Widget build(BuildContext context) =>
      SkylineSection(title: title, subtitle: subtitle, child: child);
}
