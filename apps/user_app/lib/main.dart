import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

import 'core/theme/deep_signal/deep_signal_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/view/registration_screen.dart';
import 'features/home/view/home_screen.dart';

/// Entry point for the Sarthi customer app.
///
/// The app is bootstrapped through [MCPToolkitBinding] so the flutter-mcp-toolkit
/// server can inspect and drive it during development. This binding is a no-op in
/// release builds. [ProviderScope] is the Riverpod root for app-wide state.
Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () => runApp(const ProviderScope(child: SarthiUserApp())),
  );
}

class SarthiUserApp extends ConsumerWidget {
  const SarthiUserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Deep Signal two-mode design language. The mode follows the OS setting
    // (ThemeMode.system) until the user overrides it with the in-app toggle
    // (see [ThemeModeToggle]).
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Sarthi',
      theme: DeepSignalTheme.light(),
      darkTheme: DeepSignalTheme.dark(),
      themeMode: themeMode,
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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // A storage read failure just means "not logged in" — start onboarding.
      error: (_, __) => const RegistrationScreen(),
      data: (session) => session != null
          ? HomeScreen(user: session.user)
          : const RegistrationScreen(),
    );
  }
}
