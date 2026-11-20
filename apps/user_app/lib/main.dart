import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'core/brand/mojud_brand.dart';
import 'core/config/api_config.dart';
import 'core/services/crash_reporting.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/view/registration_screen.dart';
import 'features/home/view/user_home_shell.dart';
import 'features/ride/view/widgets/vast_quiet/vast_quiet_theme.dart'
    show RideSurfaces;
import 'features/splash/view/splash_screen.dart';
import 'features/update/view/update_gate.dart';

/// Entry point for the MOJUD customer app.
///
/// The app is bootstrapped through [MCPToolkitBinding] so the flutter-mcp-toolkit
/// server can inspect and drive it during development. This binding is a no-op in
/// release builds. [ProviderScope] is the Riverpod root for app-wide state.
///
/// [CrashReporting] sends uncaught errors to Firebase Crashlytics in release
/// builds only, and stays off when Firebase isn't configured.
Future<void> main() async {
  // A release build without a server address stops here, not at loopback.
  ApiConfig.ensureConfigured();
  final crashReporting = CrashReporting();
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () async {
      // Before the first frame, so an error while building it is reported.
      await crashReporting.start();
      runApp(const ProviderScope(child: MojudUserApp()));
    },
    // Uncaught async errors land in the binding's guarded zone, not in
    // PlatformDispatcher.onError: report them, and keep the MCP error log.
    onZoneError: (error, stack) {
      crashReporting.recordZoneError(error, stack);
      MCPToolkitBinding.instance.handleZoneError(error, stack);
    },
  );
}

class MojudUserApp extends StatelessWidget {
  const MojudUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The Skyline design language (Deep Signal's blues, rounded and friendly),
    // light only — the app does not follow the OS dark setting or offer a
    // theme switch.
    return MaterialApp(
      title: MojudBrand.name,
      theme: SkylineTheme.light(
        extensions: [RideSurfaces(wash: SkylineTokens.light.primarySoft)],
      ),
      themeMode: ThemeMode.light,
      // Above the navigator, so a build the backend no longer serves is
      // stopped whichever screen is open.
      builder: (context, child) => UpdateGate(child: child!),
      home: const _AppRoot(),
    );
  }
}

/// Routes between onboarding and the home experience based on the persistent
/// session in [authControllerProvider]. On launch that provider hydrates from
/// secure storage (hence the brief loading state), so a returning user with a
/// saved token lands straight on Home without re-authenticating.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    return session.when(
      loading: () => const SplashScreen(),
      // A storage read failure just means "not logged in" — start onboarding.
      error: (_, __) => const RegistrationScreen(),
      data: (session) => session != null
          ? UserHomeShell(user: session.user)
          : const RegistrationScreen(),
    );
  }
}
