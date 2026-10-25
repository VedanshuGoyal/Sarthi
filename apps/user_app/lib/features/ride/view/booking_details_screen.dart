import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/pickup_location.dart';
import '../domain/round_trip_booking.dart';
import '../domain/scheduling.dart' show tooSoonHint;
import '../ride_providers.dart';
import '../view_model/booking_details_view_model.dart';
import '../view_model/trip_start_view_model.dart';
import 'pickup_location_screen.dart';
import 'widgets/add_car_sheet.dart';
import 'widgets/car_selector_field.dart';
import 'widgets/fare_summary.dart';
import 'widgets/ride_theme.dart';
import 'widgets/hours_selector.dart';
import 'widgets/schedule_field.dart';
import 'widgets/time_slot_picker.dart';
import 'widgets/trip_start_row.dart';

/// The Round Trip booking page: pickup, how long, when, and which car.
///
/// The pickup row on top is filled from GPS as the page opens
/// ([tripStartViewModelProvider], shared with One-Way's "From" row); tapping
/// it opens the pickup search to change it. Below, the customer picks the hire
/// duration, a start date/time, and one of their saved cars from the same
/// dropdown One-Way uses (adding a car inline when needed). On confirm the
/// assembled [RoundTripBooking] is handed back via [onConfirmed]. Form state
/// lives in [bookingDetailsViewModelProvider]; this view only renders it and
/// drives the pickers.
class BookingDetailsScreen extends ConsumerWidget {
  const BookingDetailsScreen({super.key, this.onConfirmed});

  /// Invoked with the assembled booking when the CTA is tapped. Defaults to
  /// popping the screen and returning the booking to the previous route.
  final void Function(BuildContext context, RoundTripBooking booking)?
  onConfirmed;

  Future<void> _pickDate(
    BuildContext context,
    BookingDetailsViewModel vm,
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
    BookingDetailsViewModel vm,
  ) async {
    final picked = await showTimeSlotPicker(
      context,
      initial: TimeOfDay.fromDateTime(vm.scheduledAt),
      isAvailable: (slot) =>
          vm.isStartAvailable(ScheduleField.withTime(vm.scheduledAt, slot)),
    );
    if (picked != null) {
      vm.setScheduledAt(ScheduleField.withTime(vm.scheduledAt, picked));
    }
  }

  /// Opens the pickup search; whatever the customer picks replaces the GPS
  /// spot.
  Future<void> _pickPickup(BuildContext context, TripStartViewModel vm) async {
    final pickup = await Navigator.of(context).push<PickupLocation>(
      MaterialPageRoute(builder: (_) => const PickupLocationScreen()),
    );
    if (pickup != null) vm.setStart(pickup);
  }

  void _confirm(BuildContext context, RoundTripBooking booking) {
    if (onConfirmed != null) return onConfirmed!(context, booking);
    Navigator.of(context).pop(booking);
  }

  /// The "why the fare is an estimate" note behind the fare's `*` marker.
  void _showFareNote(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estimated fare'),
        content: const Text(
          'Prices may vary based on the final pickup or drop location and the '
          'time taken.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Opens the add-car sheet and selects whatever car it saved.
  Future<void> _addCar(BuildContext context, WidgetRef ref) async {
    final car = await showAddCarSheet(context);
    if (car == null || !context.mounted) return;
    ref.read(bookingDetailsViewModelProvider).selectCar(car);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(bookingDetailsViewModelProvider);
    final start = ref.watch(tripStartViewModelProvider);
    final savedCars = ref.watch(savedCarsViewModelProvider);
    final theme = Theme.of(context);
    final pickup = start.start;
    final booking = pickup == null ? null : vm.bookingFrom(pickup);
    final String? hint = switch ((pickup, vm.car)) {
      (null, _) when start.isLocating => 'Finding your location…',
      (null, _) => 'Choose your pickup to continue.',
      (_, null) => 'Choose your car to continue.',
      _ when vm.isTooSoon => tooSoonHint,
      _ => null,
    };

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
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        TripStartRow(
                          label: 'Pickup',
                          start: pickup,
                          isLocating: start.isLocating,
                          isCurrentLocation: start.isCurrentLocation,
                          onTap: () => _pickPickup(context, start),
                        ),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'How long?',
                          subtitle: 'Hire a driver by the hour.',
                          child: HoursSelector(
                            hours: vm.hours,
                            quickHours: BookingDetailsViewModel.quickHours,
                            canDecrement: vm.canDecrementHours,
                            canIncrement: vm.canIncrementHours,
                            onDecrement: vm.decrementHours,
                            onIncrement: vm.incrementHours,
                            onQuickPick: vm.setHours,
                          ),
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
                  SkylineActionBar(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FareSummary(
                            fare: vm.fare,
                            hours: vm.hours,
                            approximate: !vm.canConfirm,
                            onDisclaimerTap: () => _showFareNote(context),
                          ),
                        ),
                        if (hint != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              hint,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        SarthiPrimaryButton(
                          label: 'Confirm booking',
                          onPressed: booking == null
                              ? null
                              : () => _confirm(context, booking),
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
  Widget build(BuildContext context) =>
      SkylineSection(title: title, subtitle: subtitle, child: child);
}
