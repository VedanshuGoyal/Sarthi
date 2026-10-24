import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/google_maps_config.dart';
import '../../../core/maps/web_maps_loader.dart';
import '../domain/geo_point.dart';
import '../domain/pickup_location.dart';
import '../ride_providers.dart';
import '../view_model/map_pickup_view_model.dart';
import 'widgets/map_pin_card.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

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
    // No Google Maps key in this build: say so plainly rather than building a
    // map that cannot render.
    if (!GoogleMapsConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _mapsError =
              "The map isn't set up yet. Go back and search for your "
              'pickup instead.';
        });
      }
      return;
    }
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

    final t = SkylineTokens.of(context);
    final showMap = _mapsError == null && vm.isReady && _mapsReady;

    return Scaffold(
      // The map runs full-bleed behind a transparent bar; only the round back
      // button floats over it.
      extendBodyBehindAppBar: showMap,
      appBar: AppBar(
        backgroundColor: showMap ? Colors.transparent : null,
        title: showMap ? null : const Text('Pin on map'),
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: Skyline.s16),
          child: Center(
            child: _FloatingSquareButton(
              tooltip: 'Back',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      body: _mapsError != null
          ? _errorState(_mapsError!)
          : !showMap
          ? const Center(child: CircularProgressIndicator())
          : Stack(
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
                // Fixed centre pin: the map slides beneath it, so its target is
                // always the map's centre.
                _CenterPin(lifted: vm.isMoving),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(Skyline.s16),
                            child: _FloatingSquareButton(
                              tooltip: 'Use my current location',
                              icon: Icons.my_location_rounded,
                              iconColor: t.primaryText,
                              onPressed: () => _locateMe(vm),
                            ),
                          ),
                          MapPinCard(
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
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
  const _CenterPin({required this.lifted});

  /// The pin lifts slightly while the map is being dragged.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return IgnorePointer(
      child: Center(
        child: AnimatedSlide(
          // The pin's tip (bottom of the stem) rests on the map's centre.
          offset: Offset(0, lifted ? -0.62 : -0.5),
          duration: Skyline.motion,
          curve: Skyline.easing,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.signal,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.surface, width: 3),
                  boxShadow: t.floatShadow,
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: t.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: t.signal,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white rounded-square button that floats over the map.
class _FloatingSquareButton extends StatelessWidget {
  const _FloatingSquareButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Skyline.radius),
        boxShadow: t.floatShadow,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: iconColor ?? t.ink),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Skyline.radius),
          ),
        ),
      ),
    );
  }
}
