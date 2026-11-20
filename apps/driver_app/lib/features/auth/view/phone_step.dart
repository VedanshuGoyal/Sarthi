import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../driver_auth_providers.dart';

/// Step 1 — collect the driver's +91 mobile number.
class PhoneStep extends ConsumerStatefulWidget {
  const PhoneStep({super.key});

  @override
  ConsumerState<PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends ConsumerState<PhoneStep> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Pre-fill if the driver came back from the OTP step.
    final vm = ref.read(driverRegistrationViewModelProvider);
    _controller = TextEditingController(text: vm.phoneNational);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(driverRegistrationViewModelProvider);
    final l10n = context.l10n;
    return SarthiFormScaffold(
      title: l10n.authPhoneTitle,
      subtitle: l10n.authPhoneSubtitle,
      fields: [
        SarthiPhoneField(
          label: l10n.authMobileNumberLabel,
          controller: _controller,
          autofocus: true,
          errorText: vm.errorText,
          onChanged: vm.onPhoneChanged,
          onSubmitted: (_) => vm.submitPhone(),
        ),
      ],
      footer: SarthiPrimaryButton(
        label: l10n.commonContinue,
        isLoading: vm.isLoading,
        onPressed: vm.submitPhone,
      ),
    );
  }
}
