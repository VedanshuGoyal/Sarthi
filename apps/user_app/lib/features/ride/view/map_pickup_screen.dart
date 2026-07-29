import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/maps/web_maps_loader.dart';
import '../domain/geo_point.dart';
import '../domain/pickup_location.dart';
import '../ride_providers.dart';
import '../view_model/map_pickup_view_model.dart';
import 'widgets/map_pin_card.dart';

/// Pick a pickup by panning a Google map under a fixed centre pin.
///
/// The map only *renders*: as the camera moves it hands the centre coordinate
/// to [mapPickupViewModelProvider], which reverse-geocodes it (via the same Ola
/// repository as the search step) into a confirmable [PickupLocation]. On
/// confirm the pickup is returned to the previous route, mirroring
/// `PickupLocationScreen`. The camera controller is a view-local rendering
/// concern (like a `ScrollController`); all data access stays in the view model.
class MapPickupScreen extends ConsumerStatefulWidget {
  const MapPickupScreen({super.key, this.onConfirmed});

  /// Invoked with the confirmed pickup. Defaults to popping and returning it.
  final void Function(BuildContext context, PickupLocation pickup)? onConfirmed;

  @override
  ConsumerState<MapPickupScreen> createState() => _MapPickupScreenState();
}

class _MapPickupScreenState extends ConsumerState<MapPickupScreen> {
  GoogleMapController? _map;
  bool _initStarted = false;

  /// Whether the platform map SDK is ready to build a `GoogleMap`. Instant on
  /// mobile (native SDK); on web it awaits the injected Maps JS SDK.
  bool _mapsReady = false;
  String? _mapsError;

  static LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);
  static GeoPoint _toGeo(LatLng p) =>
      GeoPoint(latitude: p.latitude, longitude: p.longitude);

  @override
  void initState() {
    super.initState();
    // Resolve the opening camera target (current location, else fallback)
    // before the map builds. Deferred so the provider is read post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initStarted) {
        _initStarted = true;
        ref.read(mapPickupViewModelProvider).init();
      }
    });
    _loadMapsSdk();
  }

  Future<void> _loadMapsSdk() async {
    try {
      await ensureWebMapsReady();
      if (mounted) setState(() => _mapsReady = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _mapsError =
              "Couldn't load the map. Check your connection, or that the "
              'Maps API key allows this site.';
        });
      }
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  void _confirm(PickupLocation pickup) {
    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) return onConfirmed(context, pickup);
    Navigator.of(context).pop(pickup);
  }

  Future<void> _locateMe(MapPickupViewModel vm) async {
    final point = await vm.locateMe();
    if (point != null) {
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(_toLatLng(point), 16),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(mapPickupViewModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pin on map')),
      body: _mapsError != null
          ? _errorState(_mapsError!)
          : (!vm.isReady || !_mapsReady)
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _toLatLng(vm.initialCenter),
                      zoom: 16,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (c) => _map = c,
                    onCameraMove: (pos) => vm.onCameraMove(_toGeo(pos.target)),
                    onCameraIdle: vm.onCameraIdle,
                  ),
                  // Fixed centre pin: the map slides beneath it, so its target
                  // is always the map's centre. Nudged up by the icon's own
                  // height so the point sits on the centre, not the tip's base.
                  const _CenterPin(),
                  Positioned(
                    right: 16,
                    bottom: 16 + 168,
                    child: FloatingActionButton.small(
                      heroTag: 'locateMe',
                      onPressed: () => _locateMe(vm),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: MapPinCard(
                        label: vm.pinLabel,
                        isMoving: vm.isMoving,
                        isResolving: vm.isResolving,
                        error: vm.error,
                        canConfirm: vm.canConfirm,
                        onConfirm: () {
                          final pickup = vm.resolved;
                          if (pickup != null) _confirm(pickup);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _errorState(String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _mapsError = null;
                  _mapsReady = false;
                });
                _loadMapsSdk();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stationary marker centred over the map. Purely decorative — the pinned
/// coordinate comes from the camera target, not from this widget.
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return IgnorePointer(
      child: Align(
        // Shift up half the icon so the pin's tip rests on the exact centre.
        alignment: const Alignment(0, -0.06),
        child: Icon(Icons.location_pin, size: 48, color: color),
      ),
    );
  }
}
