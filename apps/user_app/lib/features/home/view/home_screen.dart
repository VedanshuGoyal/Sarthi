import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_user.dart';
import '../../ride/domain/pickup_location.dart';
import '../../ride/domain/trip_type.dart';
import '../../ride/view/pickup_location_screen.dart';
import '../../ride/view/trip_type_selector.dart';
import '../../ride/view_model/trip_selection_view_model.dart';

/// Landing screen shown after a customer finishes registering.
///
/// Greets the user, then hosts the [TripTypeSelector] so they can pick how they
/// want to travel. The body is centred and width-capped on large screens and
/// scrolls on short ones, per the responsive-layout guideline.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.user});

  final AuthUser user;

  /// Revokes the session on the server (best-effort), then wipes it from memory
  /// and secure storage — returning the app to onboarding.
  Future<void> _logout(WidgetRef ref) async {
    final auth = ref.read(authControllerProvider.notifier);
    final token = auth.token;
    if (token != null) {
      try {
        await ref.read(authRepositoryProvider).logout(token);
      } catch (_) {
        // Already clearing locally; a failed server revoke shouldn't block it.
      }
    }
    await auth.signOut();
  }

  /// Routes the confirmed trip choice to its next step. Round Trip advances to
  /// the pickup-location step; Multi-Stop is not built yet.
  Future<void> _onTripSelected(
    BuildContext context,
    TripSelectionViewModel vm,
  ) async {
    switch (vm.selectedType!) {
      case TripType.roundTrip:
        final pickup = await Navigator.of(context).push<PickupLocation>(
          MaterialPageRoute(builder: (_) => const PickupLocationScreen()),
        );
        if (pickup != null && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('Pickup set: ${pickup.address}')),
            );
        }
      case TripType.multiStop:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Multi-Stop trips are coming soon.')),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final firstName = user.name.split(' ').first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sarthi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => _logout(ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hi $firstName, how can we drive you?',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a trip type to get started.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TripTypeSelector(
                    onContinue: (vm) => _onTripSelected(context, vm),
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
