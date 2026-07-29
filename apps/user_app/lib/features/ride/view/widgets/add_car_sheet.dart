import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../data/cars_repository.dart';
import '../../domain/car.dart';
import '../../domain/car_type.dart';
import '../../domain/transmission.dart';
import '../../ride_providers.dart';
import 'car_options_fields.dart';

/// Opens the add-car sheet and resolves with the saved [Car], or null when the
/// customer backs out. The caller usually selects the returned car.
Future<Car?> showAddCarSheet(BuildContext context) {
  return showModalBottomSheet<Car>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AddCarSheet(),
  );
}

/// The "add a car" form: registration number plus the shared car-type and
/// transmission dropdowns. Saving goes through [savedCarsViewModelProvider]
/// (never a service directly, per MVVM); on success the sheet pops with the
/// stored car so the booking step can select it.
class AddCarSheet extends ConsumerStatefulWidget {
  const AddCarSheet({super.key});

  @override
  ConsumerState<AddCarSheet> createState() => _AddCarSheetState();
}

class _AddCarSheetState extends ConsumerState<AddCarSheet> {
  final _registration = TextEditingController();
  CarType? _carType;
  Transmission _transmission = Transmission.automatic;

  /// The server's message when the last save failed; cleared on edit.
  String? _errorMessage;

  @override
  void dispose() {
    _registration.dispose();
    super.dispose();
  }

  /// The plate as the backend stores it: uppercase, separators stripped.
  String get _normalizedRegistration =>
      _registration.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  /// Mirrors the backend's permissive length bound (formats vary too much for
  /// a strict pattern), so obviously bad plates fail before a request is sent.
  bool get _registrationValid {
    final length = _normalizedRegistration.length;
    return length >= 4 && length <= 16;
  }

  bool get _canSave =>
      _registrationValid &&
      _carType != null &&
      !ref.read(savedCarsViewModelProvider).isSaving;

  Future<void> _save() async {
    setState(() => _errorMessage = null);
    try {
      final car = await ref
          .read(savedCarsViewModelProvider)
          .addCar(
            registration: _normalizedRegistration,
            type: _carType!,
            transmission: _transmission,
          );
      if (mounted) Navigator.of(context).pop(car);
    } on CarsRequestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } on Exception {
      if (mounted) {
        setState(() => _errorMessage = "Couldn't save the car. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSaving = ref.watch(
      savedCarsViewModelProvider.select((vm) => vm.isSaving),
    );

    return Padding(
      // Keep the form above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add a car',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Saved once, offered on every booking.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SarthiTextField(
              label: 'Registration number',
              controller: _registration,
              hintText: 'e.g. KA 01 AB 1234',
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9 -]')),
              ],
              errorText: _registration.text.isNotEmpty && !_registrationValid
                  ? 'Enter the full registration number.'
                  : null,
              onChanged: (_) => setState(() => _errorMessage = null),
            ),
            const SizedBox(height: 16),
            CarOptionsFields(
              carType: _carType,
              transmission: _transmission,
              onCarTypeChanged: (type) => setState(() {
                _carType = type;
                _errorMessage = null;
              }),
              onTransmissionChanged: (value) => setState(() {
                _transmission = value;
                _errorMessage = null;
              }),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SarthiPrimaryButton(
              label: isSaving ? 'Saving…' : 'Save car',
              onPressed: _canSave ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
