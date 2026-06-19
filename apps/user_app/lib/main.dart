import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const _HomePlaceholder(),
    );
  }
}

/// Temporary landing screen. Replaced by features/home once the map view lands.
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sarthi')),
      body: const Center(child: Text('Where to?')),
    );
  }
}
