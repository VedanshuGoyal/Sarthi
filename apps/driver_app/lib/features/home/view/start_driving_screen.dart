import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../../auth/view/registration_screen.dart';
import '../../language/view/language_switch.dart';

/// The driver app's landing screen — shown to every signed-out driver before
/// registration. A single CTA ("Start Driving") pushes [RegistrationScreen],
/// which runs the phone → OTP → name flow.
class StartDrivingScreen extends StatelessWidget {
  const StartDrivingScreen({super.key});

  void _startDriving(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegistrationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      // English or Hindi before sign-up, whatever the phone is set to.
      appBar: AppBar(actions: const [LanguageMenuButton()]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.local_taxi_outlined,
                    size: 96,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    l10n.appTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.startTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SarthiPrimaryButton(
                    label: l10n.startDriving,
                    onPressed: () => _startDriving(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
