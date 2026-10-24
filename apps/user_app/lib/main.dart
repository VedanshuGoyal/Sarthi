import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'core/brand/mojud_brand.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/view/registration_screen.dart';
import 'features/home/view/home_screen.dart';
import 'features/ride/view/widgets/vast_quiet/vast_quiet_theme.dart'
    show RideSurfaces;
import 'features/splash/view/splash_screen.dart';

/// Entry point for the MOJUD customer app.
///
/// The app is bootstrapped through [MCPToolkitBinding] so the flutter-mcp-toolkit
/// server can inspect and drive it during development. This binding is a no-op in
/// release builds. [ProviderScope] is the Riverpod root for app-wide state.
Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () => runApp(const ProviderScope(child: MojudUserApp())),
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
          ? HomeScreen(user: session.user)
          : const RegistrationScreen(),
    );
  }
}
