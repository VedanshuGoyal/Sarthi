import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/pickup_location.dart';
import '../ride_providers.dart';
import '../view_model/pickup_selection_view_model.dart';
import 'map_pickup_screen.dart';
import 'widgets/current_location_button.dart';
import 'widgets/pickup_suggestion_tile.dart';
import 'widgets/recent_location_tile.dart';

/// Step 2 of a Round Trip booking: choose where the driver picks you up.
///
/// A search field (Ola Maps autocomplete) plus a "use my current location"
/// shortcut (GPS + reverse-geocode). Watches [pickupSelectionViewModelProvider]
/// and, on confirm, hands the chosen [PickupLocation] back via [onConfirmed].
/// Body is width-capped and centred on large screens per the responsive guide.
class PickupLocationScreen extends ConsumerStatefulWidget {
  const PickupLocationScreen({super.key, this.onConfirmed});

  /// Invoked with the confirmed pickup when the CTA is tapped. Defaults to
  /// popping the screen and returning the location to the previous route.
  final void Function(BuildContext context, PickupLocation pickup)? onConfirmed;

  @override
  ConsumerState<PickupLocationScreen> createState() =>
      _PickupLocationScreenState();
}

class _PickupLocationScreenState extends ConsumerState<PickupLocationScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Mirrors a programmatic pickup choice (suggestion tap / current location)
  /// back into the text field without re-triggering a search.
  void _syncField(PickupSelectionViewModel vm) {
    if (_controller.text != vm.query) {
      _controller.value = TextEditingValue(
        text: vm.query,
        selection: TextSelection.collapsed(offset: vm.query.length),
      );
    }
  }

  void _confirm(PickupLocation pickup) {
    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) return onConfirmed(context, pickup);
    Navigator.of(context).pop(pickup);
  }

  /// Opens the map picker; a pinned pickup comes back as the selection so the
  /// customer can confirm it like any search result.
  Future<void> _pickOnMap(PickupSelectionViewModel vm) async {
    final pickup = await Navigator.of(context).push<PickupLocation>(
      MaterialPageRoute(builder: (_) => const MapPickupScreen()),
    );
    if (pickup == null) return;
    vm.selectFromMap(pickup);
    _syncField(vm);
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(pickupSelectionViewModelProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Set pickup')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SarthiTextField(
                    label: 'Pickup location',
                    controller: _controller,
                    hintText: 'Search for a place',
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    prefixIcon: const Icon(Icons.search),
                    onChanged: vm.onQueryChanged,
                  ),
                  if (vm.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      vm.error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  CurrentLocationButton(
                    isBusy: vm.isLocating,
                    onPressed: () async {
                      await vm.useCurrentLocation();
                      _syncField(vm);
                    },
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      Icons.map_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      'Select on map',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _pickOnMap(vm),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _results(vm, theme)),
                  const SizedBox(height: 8),
                  SarthiPrimaryButton(
                    label: 'Confirm pickup',
                    onPressed: vm.canConfirm
                        ? () async {
                            final pickup = vm.selected!;
                            await vm.rememberSelected();
                            if (context.mounted) _confirm(pickup);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(PickupSelectionViewModel vm, ThemeData theme) {
    if (vm.isSearching && vm.suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.suggestions.isNotEmpty) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: vm.suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final suggestion = vm.suggestions[i];
          return PickupSuggestionTile(
            suggestion: suggestion,
            onTap: () {
              vm.selectSuggestion(suggestion);
              _syncField(vm);
            },
          );
        },
      );
    }
    // No live results: offer recent pickups when the field is empty.
    if (vm.query.isEmpty && vm.recents.isNotEmpty) {
      return _recentsList(vm, theme);
    }
    return Center(
      child: Text(
        vm.canConfirm
            ? 'Pickup set. Tap confirm to continue.'
            : 'Search for your pickup, or use your current location.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _recentsList(PickupSelectionViewModel vm, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(
            'Recent',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: vm.recents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final recent = vm.recents[i];
              return RecentLocationTile(
                location: recent,
                onTap: () {
                  vm.selectRecent(recent);
                  _syncField(vm);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
