import 'package:flutter/material.dart';

import '../../domain/car_type.dart';
import '../../domain/transmission.dart';
import 'option_dropdown.dart';

/// The car-type and transmission dropdowns every booking step shares:
/// side-by-side on wide viewports, stacked on phones.
///
/// State-free per the reusable-widget guideline: it renders the current picks
/// and emits changes; the parent owns the choice. Round Trip and One-Way use
/// this same pair so the "which car?" question always looks identical.
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

  /// Names for each [CarType], in the enum's cheapest-to-premium order.
  static const _carTypes = <(CarType, String)>[
    (CarType.hatchback, 'Hatchback'),
    (CarType.sedan, 'Sedan'),
    (CarType.suv, 'SUV'),
    (CarType.luxury, 'Luxury'),
  ];

  static const _transmissions = <(Transmission, String)>[
    (Transmission.automatic, 'Automatic'),
    (Transmission.manual, 'Manual'),
  ];

  /// The display name for [type], for screens that echo the pick read-only.
  /// Here so the label always matches what the dropdown showed.
  static String carTypeLabel(CarType type) =>
      _carTypes.firstWhere((option) => option.$1 == type).$2;

  static String transmissionLabel(Transmission value) =>
      _transmissions.firstWhere((option) => option.$1 == value).$2;

  @override
  Widget build(BuildContext context) {
    final carTypeField = OptionDropdown<CarType>(
      label: 'Car type',
      value: carType,
      hintText: 'Select car type',
      options: _carTypes,
      onChanged: onCarTypeChanged,
    );
    final transmissionField = OptionDropdown<Transmission>(
      label: 'Transmission',
      value: transmission,
      options: _transmissions,
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
