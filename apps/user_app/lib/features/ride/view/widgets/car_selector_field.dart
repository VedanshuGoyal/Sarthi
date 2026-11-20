import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/car.dart';
import 'car_options_fields.dart';
import 'option_dropdown.dart';

/// The "which car?" picker every booking step shares: a dropdown of the
/// customer's saved cars plus an "Add a car" action.
///
/// State-free per the reusable-widget guideline: it renders the list/selection
/// it is given and emits events; the saved-cars view model owns the list and
/// the booking step's view model owns the selection. Round Trip and One-Way
/// use this same field so the "which car?" question always looks identical.
class CarSelectorField extends StatelessWidget {
  const CarSelectorField({
    super.key,
    required this.cars,
    required this.selected,
    required this.onSelected,
    required this.onAddCar,
    this.isLoading = false,
    this.loadFailed = false,
    this.onRetry,
  });

  /// The customer's saved cars, newest first.
  final List<Car> cars;

  /// The chosen car; null until the customer picks one.
  final Car? selected;

  final ValueChanged<Car> onSelected;

  /// Opens the add-car flow (the parent shows the sheet and selects the
  /// result).
  final VoidCallback onAddCar;

  /// True while the saved-car list is being fetched.
  final bool isLoading;

  /// True when fetching the list failed; pair with [onRetry].
  final bool loadFailed;
  final VoidCallback? onRetry;

  /// One line naming a saved car, e.g. "KA01AB1234 · Sedan · Automatic".
  /// Shared with the screens that echo the pick read-only.
  static String carLabel(Car car) =>
      '${car.registration}'
      ' · ${CarOptionsFields.carTypeLabel(car.type)}'
      ' · ${CarOptionsFields.transmissionLabel(car.transmission)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (isLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(l10n.carsLoading, style: theme.textTheme.bodyMedium),
          ),
        ],
      );
    }

    if (loadFailed) {
      return Row(
        children: [
          Expanded(
            child: Text(
              l10n.carsLoadFailed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(l10n.carsRetry)),
        ],
      );
    }

    // A selection that isn't in the list (e.g. the list was refreshed away)
    // can't be rendered by the dropdown; fall back to the placeholder.
    final value = selected != null && cars.contains(selected) ? selected : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cars.isEmpty)
          Text(
            l10n.carsNoneYet,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          OptionDropdown<Car>(
            label: l10n.carsYourCar,
            value: value,
            hintText: l10n.carsSelectYourCar,
            options: [for (final car in cars) (car, carLabel(car))],
            onChanged: onSelected,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAddCar,
            icon: const Icon(Icons.add),
            label: Text(l10n.carsAdd),
          ),
        ),
      ],
    );
  }
}
