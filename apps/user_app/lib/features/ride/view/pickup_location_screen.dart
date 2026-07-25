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

/// Choose a location: the Round Trip pickup by default, but reusable for any
/// "pick a place" step (a Multi-Stop starting point or stop) via the labels.
///
/// A search field (Ola Maps autocomplete) plus a "use my current location"
/// shortcut (GPS + reverse-geocode). Tapping any result — a suggestion, a
/// recent, the GPS shortcut, or a map pin — is the whole decision: the choice
/// is remembered and handed straight back via [onConfirmed], with no separate
/// confirm step. Watches [pickupSelectionViewModelProvider]. Body is
/// width-capped and centred on large screens per the responsive guide.
class PickupLocationScreen extends ConsumerStatefulWidget {
  const PickupLocationScreen({
    super.key,
    this.title = 'Set pickup',
    this.fieldLabel = 'Pickup location',
    this.onConfirmed,
  });

  /// The app-bar title and search-field label — overridden when the screen is
  /// choosing something other than a Round Trip pickup.
  final String title;
  final String fieldLabel;

  /// Invoked with the chosen pickup as soon as one is tapped. Defaults to
  /// popping the screen and returning the location to the previous route.
  final void Function(BuildContext context, PickupLocation pickup)? onConfirmed;

  @override
  ConsumerState<PickupLocationScreen> createState() =>
      _PickupLocationScreenState();
}

class _PickupLocationScreenState extends ConsumerState<PickupLocationScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Seed the field with any pre-set query (previews/tests); afterwards the
    // field is only ever edited by the user — every choice leaves the screen.
    _controller.text = ref.read(pickupSelectionViewModelProvider).query;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Completes the step with [pickup]: persists it to recents (best-effort)
  /// and hands it back. A null [pickup] means the tap couldn't be resolved —
  /// the view model has already surfaced why, so we stay put.
  Future<void> _choose(
    PickupSelectionViewModel vm,
    PickupLocation? pickup,
  ) async {
    if (pickup == null) return;
    await vm.rememberSelected();
    if (!mounted) return;
    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) return onConfirmed(context, pickup);
    Navigator.of(context).pop(pickup);
  }

  /// Opens the map picker; a pinned pickup comes straight back as the chosen
  /// location.
  Future<void> _pickOnMap(PickupSelectionViewModel vm) async {
    final pickup = await Navigator.of(context).push<PickupLocation>(
      MaterialPageRoute(builder: (_) => const MapPickupScreen()),
    );
    if (pickup == null || !mounted) return;
    await _choose(vm, vm.selectFromMap(pickup));
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(pickupSelectionViewModelProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                    label: widget.fieldLabel,
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
                    onPressed: () async =>
                        _choose(vm, await vm.useCurrentLocation()),
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
            onTap: () => _choose(vm, vm.selectSuggestion(suggestion)),
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
        'Search for a place, or use your current location.',
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
                onTap: () => _choose(vm, vm.selectRecent(recent)),
              );
            },
          ),
        ),
      ],
    );
  }
}
