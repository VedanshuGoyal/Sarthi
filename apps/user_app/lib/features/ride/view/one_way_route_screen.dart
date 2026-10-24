import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/one_way_trip.dart';
import '../domain/pickup_location.dart';
import '../ride_providers.dart';
import '../view_model/pickup_selection_view_model.dart';
import '../view_model/trip_start_view_model.dart';
import 'pickup_location_screen.dart';
import 'widgets/trip_start_row.dart';

/// Step 2 of a One-Way trip: where from and where to, on one page.
///
/// The starting point is filled from GPS as the page opens
/// ([tripStartViewModelProvider]), so usually the customer only types a
/// destination. The search, recents and map picker are [PickupLocationScreen]'s,
/// with a "From" row on top that opens a starting-point picker. Tapping a
/// destination completes the step and hands back the [OneWayRoute]; if no
/// starting point could be found by then, the starting-point picker opens
/// first.
class OneWayRouteScreen extends ConsumerStatefulWidget {
  const OneWayRouteScreen({super.key, this.onConfirmed});

  /// Invoked with the route once both ends are set. Defaults to popping the
  /// screen and returning it to the previous route.
  final void Function(BuildContext context, OneWayRoute route)? onConfirmed;

  @override
  ConsumerState<OneWayRouteScreen> createState() => _OneWayRouteScreenState();
}

class _OneWayRouteScreenState extends ConsumerState<OneWayRouteScreen> {
  /// Set while a destination tap is being completed, so a second tap (e.g.
  /// while GPS is still resolving the start) can't complete the step twice.
  bool _completing = false;

  /// Opens the starting-point picker. It runs its own search state, so the
  /// destination field underneath keeps its query and results.
  Future<PickupLocation?> _pickStart(
    BuildContext context,
    TripStartViewModel vm,
  ) async {
    final start = await Navigator.of(context).push<PickupLocation>(
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          overrides: [
            pickupSelectionViewModelProvider.overrideWith(
              (ref) => PickupSelectionViewModel(
                repository: ref.watch(locationRepositoryProvider),
              ),
            ),
          ],
          child: const PickupLocationScreen(
            title: 'Set starting point',
            fieldLabel: 'Starting point',
          ),
        ),
      ),
    );
    if (start != null) vm.setStart(start);
    return start;
  }

  Future<void> _onDestination(
    BuildContext context,
    TripStartViewModel vm,
    PickupLocation destination,
  ) async {
    if (_completing) return;
    _completing = true;
    try {
      // Usually already located; otherwise wait for the fix in flight.
      var start = await vm.locate();
      if (!context.mounted) return;
      start ??= await _pickStart(context, vm);
      if (start == null || !context.mounted) return;
      final route = (start: start, destination: destination);
      final onConfirmed = widget.onConfirmed;
      if (onConfirmed != null) return onConfirmed(context, route);
      Navigator.of(context).pop(route);
    } finally {
      _completing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(tripStartViewModelProvider);
    return PickupLocationScreen(
      title: 'Where to?',
      fieldLabel: 'Destination',
      offerCurrentLocation: false,
      header: TripStartRow(
        start: vm.start,
        isLocating: vm.isLocating,
        isCurrentLocation: vm.isCurrentLocation,
        onTap: () => _pickStart(context, vm),
      ),
      onConfirmed: (context, destination) =>
          _onDestination(context, vm, destination),
    );
  }
}
