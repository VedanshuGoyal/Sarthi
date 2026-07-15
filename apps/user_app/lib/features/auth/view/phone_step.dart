import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../auth_providers.dart';

/// Step 1 — collect the customer's +91 mobile number.
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
    // Pre-fill if the user came back from the OTP step.
    final vm = ref.read(registrationViewModelProvider);
    _controller = TextEditingController(text: vm.phoneNational);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(registrationViewModelProvider);
    return SarthiFormScaffold(
      title: 'Enter your mobile number',
      subtitle: "We'll text you a one-time code to verify it's you.",
      fields: [
        SarthiPhoneField(
          controller: _controller,
          autofocus: true,
          errorText: vm.errorText,
          onChanged: vm.onPhoneChanged,
          onSubmitted: (_) => vm.submitPhone(),
        ),
      ],
      footer: SarthiPrimaryButton(
        label: 'Continue',
        isLoading: vm.isLoading,
        onPressed: vm.submitPhone,
      ),
    );
  }
}
