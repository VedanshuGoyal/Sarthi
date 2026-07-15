import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth_providers.dart';
import '../view_model/registration_view_model.dart';
import 'otp_step.dart';
import 'phone_step.dart';
import 'profile_step.dart';

/// Hosts the registration flow and swaps in the view for the current
/// [RegistrationStep] with a slide/fade transition.
///
/// It watches only the `step` so it rebuilds when the flow advances — each step
/// view manages its own field state and loading indicator.
class RegistrationScreen extends ConsumerWidget {
  const RegistrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(
      registrationViewModelProvider.select((vm) => vm.step),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.12, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: _viewFor(step),
    );
  }

  Widget _viewFor(RegistrationStep step) {
    // KeyedSubtree keys each step so AnimatedSwitcher animates between them.
    return switch (step) {
      RegistrationStep.phone => const KeyedSubtree(
        key: ValueKey('phone'),
        child: PhoneStep(),
      ),
      RegistrationStep.otp => const KeyedSubtree(
        key: ValueKey('otp'),
        child: OtpStep(),
      ),
      RegistrationStep.profile => const KeyedSubtree(
        key: ValueKey('profile'),
        child: ProfileStep(),
      ),
      // `done` is handled by the app root, which routes to Home; render the
      // profile step momentarily to avoid a flash during the transition.
      RegistrationStep.done => const KeyedSubtree(
        key: ValueKey('profile'),
        child: ProfileStep(),
      ),
    };
  }
}
