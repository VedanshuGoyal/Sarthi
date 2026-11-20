import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../../ride/data/cars_repository.dart';
import '../../../ride/domain/car.dart';
import '../../../ride/ride_labels.dart';
import '../../../ride/ride_providers.dart';
import '../../../ride/view/widgets/add_car_sheet.dart';

/// The profile's "My cars" block: every saved car with a remove action, plus
/// the same add-car sheet the booking steps use.
///
/// A `ConsumerWidget` bound to the shared saved-cars view model, so a car
/// added here is immediately offered on the next booking (both read the same
/// locally mirrored list). Removal errors surface as a snackbar.
class SavedCarsSection extends ConsumerWidget {
  const SavedCarsSection({super.key});

  Future<void> _remove(BuildContext context, WidgetRef ref, Car car) async {
    try {
      await ref.read(savedCarsViewModelProvider).removeCar(car);
    } on CarsRequestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(savedCarsViewModelProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.carsMyCars,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (vm.isLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (vm.loadFailed)
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    l10n.carsLoadFailed,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
              TextButton(onPressed: vm.load, child: Text(l10n.carsRetry)),
            ],
          )
        else if (vm.cars.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              l10n.carsNoneYet,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final car in vm.cars)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(
                Icons.directions_car_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(car.registration, style: theme.textTheme.bodyLarge),
              subtitle: Text(
                '${car.type.labelIn(l10n)}'
                ' · ${car.transmission.labelIn(l10n)}',
              ),
              trailing: vm.removing == car
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.carsRemove,
                      onPressed: vm.removing != null
                          ? null
                          : () => _remove(context, ref, car),
                    ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showAddCarSheet(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.carsAdd),
          ),
        ),
      ],
    );
  }
}
