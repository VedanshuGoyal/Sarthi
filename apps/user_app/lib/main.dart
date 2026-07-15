import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

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

class SarthiUserApp extends StatelessWidget {
  const SarthiUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarthi',
      // Shared ultramarine (#120A8F) design scheme — common to both apps.
      // Pinned to light for now regardless of the system setting.
      theme: SarthiTheme.light(),
      darkTheme: SarthiTheme.dark(),
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
