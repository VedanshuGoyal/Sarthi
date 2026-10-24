import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sarthi_shared/sarthi_shared.dart';
import '../../../core/config/google_maps_config.dart';
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
/// row that opens the map picker on the GPS fix (plain GPS + reverse-geocode
/// when no Maps key is set). Tapping any result — a suggestion, a recent, or a
/// confirmed map pin — is the whole decision: the choice
/// is remembered and handed straight back via [onConfirmed], with no separate
/// confirm step. Watches [pickupSelectionViewModelProvider]. Body is
/// width-capped and centred on large screens per the responsive guide.
class PickupLocationScreen extends ConsumerStatefulWidget {
  const PickupLocationScreen({
    super.key,
    this.title = 'Set pickup',
    this.fieldLabel = 'Pickup location',
    this.header,
    this.offerCurrentLocation = true,
    this.onConfirmed,
  });

  /// The app-bar title and search-field label — overridden when the screen is
  /// choosing something other than a Round Trip pickup.
  final String title;
  final String fieldLabel;

  /// Shown at the top of the search card, above the field — e.g. the One-Way
  /// step's "From" row.
  final Widget? header;

  /// Whether the map row is offered as "use my current location". Off for a
  /// destination, where it reads "Select on map" (and is hidden without a map).
  final bool offerCurrentLocation;

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
      MaterialPageRoute(
        builder: (_) => MapPickupScreen(caption: widget.fieldLabel),
      ),
    );
    if (pickup == null || !mounted) return;
    await _choose(vm, vm.selectFromMap(pickup));
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(pickupSelectionViewModelProvider);
    final t = SkylineTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Skyline.s20,
                Skyline.s8,
                Skyline.s20,
                Skyline.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The search field and the two ways round typing live in one
                  // card, as a single "where" control.
                  SkylineCard(
                    padding: const EdgeInsets.fromLTRB(
                      Skyline.s4,
                      Skyline.s4,
                      Skyline.s4,
                      Skyline.s4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.header case final header?) ...[
                          header,
                          Divider(color: t.hairline, height: 1),
                        ],
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: vm.onQueryChanged,
                          style: t.title(16, weight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: widget.fieldLabel,
                            hintText: 'Search for a place',
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: t.primaryText,
                            ),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                        Divider(color: t.hairline, height: 1),
                        // One row covers both "I'm here" and "it's over
                        // there": the map opens on the GPS fix, so the rider
                        // confirms as-is or nudges the pin. Without a Maps key
                        // there's no map, so it falls back to plain GPS.
                        if (!widget.offerCurrentLocation) ...[
                          if (GoogleMapsConfig.isConfigured)
                            SkylineRow(
                              icon: Icons.map_rounded,
                              title: 'Select on map',
                              accent: true,
                              onTap: () => _pickOnMap(vm),
                            ),
                        ] else if (GoogleMapsConfig.isConfigured)
                          CurrentLocationButton(
                            subtitle: 'Opens the map to adjust the pin',
                            onPressed: () => _pickOnMap(vm),
                          )
                        else
                          CurrentLocationButton(
                            isBusy: vm.isLocating,
                            onPressed: () async =>
                                _choose(vm, await vm.useCurrentLocation()),
                          ),
                      ],
                    ),
                  ),
                  if (vm.error != null) ...[
                    const SizedBox(height: Skyline.s12),
                    _ErrorNote(message: vm.error!),
                  ],
                  const SizedBox(height: Skyline.s16),
                  Expanded(child: _results(vm, t)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(PickupSelectionViewModel vm, SkylineTokens t) {
    if (vm.isSearching && vm.suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.suggestions.isNotEmpty) {
      return _listCard(
        itemCount: vm.suggestions.length,
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Skyline.s4,
              0,
              Skyline.s4,
              Skyline.s8,
            ),
            child: Text('Recent', style: t.title(15)),
          ),
          Flexible(
            child: _listCard(
              itemCount: vm.recents.length,
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
    return Padding(
      padding: const EdgeInsets.only(top: Skyline.s32),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(Skyline.radiusLg),
            ),
            child: Icon(Icons.travel_explore_rounded, color: t.primaryText),
          ),
          const SizedBox(height: Skyline.s12),
          Text(
            widget.offerCurrentLocation
                ? 'Search for a place, or use your current location.'
                : 'Search for a place, or select it on the map.',
            textAlign: TextAlign.center,
            style: t.body(size: 14),
          ),
        ],
      ),
    );
  }

  /// Results and recents in one rounded card that scrolls inside itself.
  Widget _listCard({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    // Aligned to the top so the card hugs its rows instead of stretching to
    // fill the space below the search card.
    return Align(
      alignment: Alignment.topCenter,
      child: SkylineCard(
        padding: const EdgeInsets.all(Skyline.s4),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

/// An inline error under the search card.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Skyline.s12),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Skyline.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: t.danger, size: 20),
          const SizedBox(width: Skyline.s8),
          Expanded(
            child: Text(message, style: t.body(size: 13, color: t.danger)),
          ),
        ],
      ),
    );
  }
}
