import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../driver_auth_providers.dart';
import 'consent_checkbox.dart';

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
    final l10n = context.l10n;

    return SarthiFormScaffold(
      leading: BackButton(onPressed: vm.isLoading ? null : vm.back),
      title: l10n.authNameTitle,
      subtitle: l10n.authNameSubtitle,
      fields: [
        SarthiTextField(
          label: l10n.authFullName,
          controller: _name,
          autofocus: true,
          hintText: l10n.authFullName,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          errorText: vm.errorText,
          prefixIcon: const Icon(Icons.person_outline),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        ConsentCheckbox(
          value: vm.hasConsented,
          enabled: !vm.isLoading,
          onChanged: vm.setConsent,
        ),
      ],
      footer: SarthiPrimaryButton(
        label: l10n.authCreateAccount,
        isLoading: vm.isLoading,
        // Disabled until the driver agrees to the Terms and Privacy Policy.
        onPressed: vm.hasConsented ? _submit : null,
      ),
    );
  }
}
