import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../driver_auth_providers.dart';
import '../view_model/driver_registration_view_model.dart';
import 'name_step.dart';
import 'otp_step.dart';
import 'phone_step.dart';

/// Hosts the driver registration flow and swaps in the view for the current
/// [DriverRegistrationStep] with a slide/fade transition.
///
/// It watches only the `step` so it rebuilds when the flow advances — each
/// step view manages its own field state and loading indicator.
///
/// `StartDrivingScreen` reaches this screen via `Navigator.push`, so it's a
/// route stacked on top of the app root — not the root's direct child, unlike
/// the customer app's `RegistrationScreen`. That means once sign-in completes
/// and the app root swaps itself to Home underneath, this pushed route would
/// otherwise stay on top forever showing a stale name field. So this screen
/// pops itself off the stack the moment `step` reaches `done`.
class RegistrationScreen extends ConsumerWidget {
  const RegistrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(
      driverRegistrationViewModelProvider.select((vm) => vm.step),
    );

    ref.listen(driverRegistrationViewModelProvider.select((vm) => vm.step), (
      _,
      next,
    ) {
      if (next == DriverRegistrationStep.done &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

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

  Widget _viewFor(DriverRegistrationStep step) {
    // KeyedSubtree keys each step so AnimatedSwitcher animates between them.
    return switch (step) {
      DriverRegistrationStep.phone => const KeyedSubtree(
        key: ValueKey('phone'),
        child: PhoneStep(),
      ),
      DriverRegistrationStep.otp => const KeyedSubtree(
        key: ValueKey('otp'),
        child: OtpStep(),
      ),
      DriverRegistrationStep.name => const KeyedSubtree(
        key: ValueKey('name'),
        child: NameStep(),
      ),
      // `done` is handled by the app root, which routes to Home; render the
      // name step momentarily to avoid a flash during the transition.
      DriverRegistrationStep.done => const KeyedSubtree(
        key: ValueKey('name'),
        child: NameStep(),
      ),
    };
  }
}
