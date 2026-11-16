import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../update_providers.dart';
import 'update_required_screen.dart';

/// Sits above the app's navigator (`MaterialApp.builder`) and swaps the whole
/// app, whatever screen is open, for [UpdateRequiredScreen] once the update
/// gate closes. On first build it asks the backend for the minimum build,
/// without waiting on the answer.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  /// The app's navigator.
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  @override
  void initState() {
    super.initState();
    ref.read(updateGateProvider).check();
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(updateGateProvider);
    if (!gate.updateRequired) return widget.child;
    // Its own navigator: above the app's there is no Overlay for the
    // screen's buttons and text to use.
    return Navigator(
      pages: [
        MaterialPage<void>(
          key: const ValueKey('update-required'),
          child: UpdateRequiredScreen(downloadUrl: gate.downloadUrl),
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}
