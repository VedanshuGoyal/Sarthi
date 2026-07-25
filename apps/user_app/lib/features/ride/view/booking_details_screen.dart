import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/car_type.dart';
import '../domain/pickup_location.dart';
import '../domain/round_trip_booking.dart';
import '../domain/transmission.dart';
import '../ride_providers.dart';
import '../view_model/booking_details_view_model.dart';
import 'widgets/car_options_fields.dart';
import 'widgets/fare_summary.dart';
import 'widgets/hours_selector.dart';
import 'widgets/schedule_field.dart';
import 'widgets/time_slot_picker.dart';

/// Step 3 of a Round Trip booking: how long, when, and what kind of car.
///
/// Given the confirmed [pickup], the customer picks the hire duration, a start
/// date/time, and a [CarType] and [Transmission] from the same compact
/// dropdowns One-Way uses. On confirm the assembled
/// [RoundTripBooking] is handed back via [onConfirmed]. State lives in
/// [bookingDetailsViewModelProvider], keyed on the pickup; this view only
/// renders it and drives the date/time pickers.
class BookingDetailsScreen extends ConsumerWidget {
  const BookingDetailsScreen({
    super.key,
    required this.pickup,
    this.onConfirmed,
  });

  final PickupLocation pickup;

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
    );
    if (picked != null) {
      vm.setScheduledAt(ScheduleField.withTime(vm.scheduledAt, picked));
    }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(bookingDetailsViewModelProvider(pickup));
    final theme = Theme.of(context);

    return Scaffold(
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
                      _PickupSummary(address: vm.pickup.address),
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
                        subtitle: 'Pick the car type and gearbox.',
                        child: CarOptionsFields(
                          carType: vm.carType,
                          transmission: vm.transmission,
                          onCarTypeChanged: vm.selectCarType,
                          onTransmissionChanged: vm.selectTransmission,
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FareSummary(
                          fare: vm.fare,
                          hours: vm.hours,
                          approximate: !vm.canConfirm,
                          onDisclaimerTap: () => _showFareNote(context),
                        ),
                      ),
                      if (!vm.canConfirm)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Choose a car type to continue.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      SarthiPrimaryButton(
                        label: 'Confirm booking',
                        onPressed: vm.canConfirm
                            ? () => _confirm(context, vm.booking!)
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
    );
  }
}

/// A compact, read-only banner echoing the pickup chosen on the previous step.
class _PickupSummary extends StatelessWidget {
  const _PickupSummary({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SarthiColors.ultramarineWash,
        borderRadius: BorderRadius.circular(SarthiTheme.radius),
      ),
      child: Row(
        children: [
          Icon(Icons.trip_origin, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pickup',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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
