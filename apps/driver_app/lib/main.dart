import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// Entry point for the Sarthi driver app.
///
/// [ProviderScope] is the Riverpod root for app-wide state. The driver app
/// shares the ultramarine (#120A8F) design scheme with the customer app via
/// [SarthiTheme], so both feel like one product.
void main() {
  runApp(const ProviderScope(child: SarthiDriverApp()));
}

class SarthiDriverApp extends StatelessWidget {
  const SarthiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarthi Driver',
      // Shared ultramarine (#120A8F) design scheme — common to both apps.
      // Light is white + ultramarine; dark follows the system setting.
      theme: SarthiTheme.light(),
      darkTheme: SarthiTheme.dark(),
      home: const _DriverHomePlaceholder(),
    );
  }
}

/// Temporary landing screen. Replaced by features/home once the driver
/// "Go Online" flow lands. The driver registration flow will reuse the shared
/// [SarthiPhoneField] / [SarthiPrimaryButton] widgets, mirroring the customer
/// app's onboarding.
class _DriverHomePlaceholder extends StatelessWidget {
  const _DriverHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sarthi Driver')),
      body: const Center(child: Text('Go online to start earning')),
    );
  }
}
