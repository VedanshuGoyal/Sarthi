import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../core/brand/mojud_logo.dart';
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
    // The brand band is a welcome, not a requirement: on short screens
    // (landscape phones, small windows) it gives way so the form and its
    // Continue button stay in view.
    final roomy = MediaQuery.sizeOf(context).height >= 700;
    return SarthiFormScaffold(
      header: roomy ? const _BrandHeader() : null,
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

/// The welcome band above the sign-in form: the MOJUD mark and what the app
/// does, so the first screen says what it is.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  static const _services = ['By the hour', 'One-way', 'Multi-stop'];

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Skyline.s20),
      decoration: BoxDecoration(
        color: t.isDark ? t.surface : t.primarySoft,
        borderRadius: BorderRadius.circular(Skyline.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MojudLockup(markHeight: 28),
          const SizedBox(height: Skyline.s16),
          Text('Your car, our driver.', style: t.heading(22)),
          const SizedBox(height: Skyline.s4),
          Text(
            'Book a driver for your own car, whenever you need one.',
            style: t.body(size: 14),
          ),
          const SizedBox(height: Skyline.s16),
          Wrap(
            spacing: Skyline.s8,
            runSpacing: Skyline.s8,
            children: [
              for (final service in _services)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Skyline.s12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface.withValues(alpha: t.isDark ? 0 : 1),
                    border: t.isDark ? Border.all(color: t.outline) : null,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    service,
                    style: t.label(size: 12, color: t.primaryText),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
