import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'core/location_providers.dart';
import 'features/auth/driver_auth_controller.dart';
import 'features/auth/domain/driver.dart';
import 'features/documents/document_providers.dart';
import 'features/documents/view/document_view_screen.dart';
import 'features/home/view/driver_home_shell.dart';
import 'features/home/view/start_driving_screen.dart';

/// Entry point for the Sarthi driver app.
///
/// The app is bootstrapped through [MCPToolkitBinding] so the flutter-mcp-toolkit
/// server can inspect and drive it during development. This binding is a no-op in
/// release builds. [ProviderScope] is the Riverpod root for app-wide state. The
/// driver app shares the customer app's light-only Skyline look — same
/// [SkylineTheme] from `sarthi_shared` — so both feel like one product.
Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () => runApp(const ProviderScope(child: SarthiDriverApp())),
  );
}

class SarthiDriverApp extends StatelessWidget {
  const SarthiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MOJUD Driver',
      theme: SkylineTheme.light(),
      home: const _AppRoot(),
    );
  }
}

/// Routes between onboarding and the driver home based on the persistent
/// session in [driverAuthControllerProvider]. On launch that provider hydrates
/// from secure storage (hence the brief loading state), so a returning driver
/// with a saved token lands straight on Home without re-registering.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fired as soon as the app starts, before auth/onboarding renders. It
    // runs alongside session hydration below rather than gating it — a
    // driver who denies the OS prompt still reaches onboarding/Home and is
    // asked again (or pointed to Settings) once they try to go online.
    ref.watch(locationPermissionProvider);

    final session = ref.watch(driverAuthControllerProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // A storage read failure just means "not logged in" — start onboarding.
      error: (_, _) => const StartDrivingScreen(),
      data: (session) => session == null
          ? const StartDrivingScreen()
          : _SignedInRoot(driver: session.driver),
    );
  }
}

/// Once signed in, a driver must clear the Document View's six KYC steps
/// before reaching Home — mirrors real driver apps gating "Go Online" behind
/// verification.
///
/// The gate reads the backend's KYC status, not local progress, so it survives
/// a reinstall and can't be bypassed from the device. It currently opens as
/// soon as the documents are submitted; once there's a review tool it should
/// wait for [KycStatus.verified] instead.
class _SignedInRoot extends ConsumerWidget {
  const _SignedInRoot({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submitted = ref.watch(
      documentRegistrationViewModelProvider.select((vm) => vm.isSubmitted),
    );
    return submitted
        ? DriverHomeShell(driver: driver)
        : const DocumentViewScreen();
  }
}
