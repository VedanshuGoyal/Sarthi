import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/car_type.dart';
import '../../domain/transmission.dart';
import '../../ride_labels.dart';
import 'option_dropdown.dart';

/// The car-type and transmission dropdowns of the add-car form:
/// side-by-side on wide viewports, stacked on phones.
///
/// State-free per the reusable-widget guideline: it renders the current picks
/// and emits changes; the parent owns the choice. Booking steps no longer show
/// this pair directly — they offer the saved-car dropdown (CarSelectorField),
/// and this widget describes a car once, when it is added.
class CarOptionsFields extends StatelessWidget {
  const CarOptionsFields({
    super.key,
    required this.carType,
    required this.transmission,
    required this.onCarTypeChanged,
    required this.onTransmissionChanged,
  });

  /// The chosen car class; null until the customer picks one.
  final CarType? carType;

  final Transmission transmission;
  final ValueChanged<CarType> onCarTypeChanged;
  final ValueChanged<Transmission> onTransmissionChanged;

  /// The breakpoint above which the two dropdowns sit side-by-side.
  static const double _wideBreakpoint = 560;

  /// The car types in the enum's cheapest-to-premium order, and the
  /// gearboxes, as the dropdowns list them.
  static const _carTypes = [
    CarType.hatchback,
    CarType.sedan,
    CarType.suv,
    CarType.luxury,
  ];

  static const _transmissions = [Transmission.automatic, Transmission.manual];

  /// The display name for [type], for screens that echo the pick read-only,
  /// in the app's language. The same words the dropdown shows.
  static String carTypeLabel(CarType type) => type.labelIn(L10n.current);

  static String transmissionLabel(Transmission value) =>
      value.labelIn(L10n.current);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final carTypeField = OptionDropdown<CarType>(
      label: l10n.carOptionsCarType,
      value: carType,
      hintText: l10n.carOptionsSelectCarType,
      options: [for (final type in _carTypes) (type, type.labelIn(l10n))],
      onChanged: onCarTypeChanged,
    );
    final transmissionField = OptionDropdown<Transmission>(
      label: l10n.carOptionsTransmission,
      value: transmission,
      options: [
        for (final gearbox in _transmissions) (gearbox, gearbox.labelIn(l10n)),
      ],
      onChanged: onTransmissionChanged,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: carTypeField),
              const SizedBox(width: 12),
              Expanded(child: transmissionField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            carTypeField,
            const SizedBox(height: 16),
            transmissionField,
          ],
        );
      },
    );
  }
}
