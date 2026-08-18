import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../driver_auth_providers.dart';

/// Step 3 — collect the driver's name to finish creating the account.
///
/// Drivers chauffeur the customer's own car, so registration doesn't need
/// vehicle, email, or date-of-birth details — those are collected later
/// (vehicle onboarding is a separate flow, out of scope here).
class NameStep extends ConsumerStatefulWidget {
  const NameStep({super.key});

  @override
  ConsumerState<NameStep> createState() => _NameStepState();
}

class _NameStepState extends ConsumerState<NameStep> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() =>
      ref.read(driverRegistrationViewModelProvider).submitName(_name.text);

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(driverRegistrationViewModelProvider);

    return SarthiFormScaffold(
      leading: BackButton(onPressed: vm.isLoading ? null : vm.back),
      title: "What's your name?",
      subtitle: "This is how riders will see you once you're on a trip.",
      fields: [
        SarthiTextField(
          label: 'Full name',
          controller: _name,
          autofocus: true,
          hintText: 'Full name',
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          errorText: vm.errorText,
          prefixIcon: const Icon(Icons.person_outline),
          onSubmitted: (_) => _submit(),
        ),
      ],
      footer: SarthiPrimaryButton(
        label: 'Create account',
        isLoading: vm.isLoading,
        onPressed: _submit,
      ),
    );
  }
}
