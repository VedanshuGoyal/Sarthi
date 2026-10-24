import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../auth/view/registration_screen.dart';

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
    return Scaffold(
      appBar: AppBar(),
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
                    'Sarthi Driver',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Drive customers in their own car, on your schedule. '
                    'Get matched with nearby trips the moment you go online.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SarthiPrimaryButton(
                    label: 'Start Driving',
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
