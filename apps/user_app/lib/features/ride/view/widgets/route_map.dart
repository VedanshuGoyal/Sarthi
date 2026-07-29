import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../core/config/google_maps_config.dart';
import '../../../../core/maps/web_maps_loader.dart';
import '../../domain/geo_point.dart';
import 'vast_quiet/vast_quiet_theme.dart';

/// A read-only overview map framing both ends of a route.
///
/// Drops a distinct marker on [start] (a green origin pin) and [destination]
/// (a red destination pin) over a soft terrain base map, joins them with a
/// dotted line, and frames the camera so both sit comfortably in view. The pins
/// are bundled PNG assets, resolved at the view's pixel ratio from their
/// `2.0x`/`3.0x` variants. It only *renders*: gestures are disabled,
/// so it reads as a static picture of the route and never fights the
/// surrounding scroll view. No callbacks and no data access — coordinates in, a
/// map out — per the reusable-widget guideline. Loading the platform Maps SDK
/// (a no-op on mobile, a `<script>` inject on web) is a rendering prerequisite,
/// handled here the same way [map_pickup_screen] does.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.start,
    required this.destination,
    this.startLabel,
    this.destinationLabel,
  });

  final GeoPoint start;
  final GeoPoint destination;

  /// Optional info-window titles for the two markers.
  final String? startLabel;
  final String? destinationLabel;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  GoogleMapController? _map;

  /// Whether the platform map SDK is ready to build a `GoogleMap`. Instant on
  /// mobile (native SDK); on web it awaits the injected Maps JS SDK.
  bool _mapsReady = false;
  bool _mapsFailed = false;

  /// Custom PNG pin bitmaps, decoded once from bundled assets. Null until
  /// decoded, falling back to default hued pins so a marker always shows.
  BitmapDescriptor? _startIcon;
  BitmapDescriptor? _destIcon;
  bool _iconsRequested = false;

  static const _originAsset = 'assets/markers/pin_origin.png';
  static const _destinationAsset = 'assets/markers/pin_destination.png';

  static LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  void initState() {
    super.initState();
    _loadMapsSdk();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the pins at the view's device pixel ratio, so the plugin picks the
    // right 1x/2x/3x variant. Needs a context for the image configuration, so
    // it runs here rather than in initState; guarded to load only once.
    if (!_iconsRequested) {
      _iconsRequested = true;
      _loadMarkerIcons(createLocalImageConfiguration(context));
    }
  }

  Future<void> _loadMapsSdk() async {
    try {
      await ensureWebMapsReady();
      if (mounted) setState(() => _mapsReady = true);
    } catch (_) {
      if (mounted) setState(() => _mapsFailed = true);
    }
  }

  /// Decodes the two PNG pins from bundled assets. [config] carries the device
  /// pixel ratio the plugin uses to select the matching density variant.
  Future<void> _loadMarkerIcons(ImageConfiguration config) async {
    final start = await BitmapDescriptor.asset(config, _originAsset);
    final dest = await BitmapDescriptor.asset(config, _destinationAsset);
    if (mounted) {
      setState(() {
        _startIcon = start;
        _destIcon = dest;
      });
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  /// True once a cloud Map ID is configured, so the map can render Google's
  /// [AdvancedMarker]s — which the Maps SDK (Android, iOS, and web) only draws
  /// on a Map-ID'd map. Without one we fall back to legacy [Marker]s, which
  /// still render everywhere. Both the map's [GoogleMapMarkerType] and every
  /// marker's class must agree with this flag (the plugin asserts it).
  bool get _advancedMarkers => GoogleMapsConfig.advancedMarkersEnabled;

  Set<Marker> get _markers => {
    _pin(
      id: 'start',
      position: _toLatLng(widget.start),
      icon:
          _startIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      // Both PNG pins and the fallback hued pins point down, so their tips sit
      // at the bottom — the default (0.5, 1) anchor lands them on the point.
      label: widget.startLabel,
    ),
    _pin(
      id: 'destination',
      position: _toLatLng(widget.destination),
      icon:
          _destIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      label: widget.destinationLabel,
    ),
  };

  /// Builds one route pin, as an [AdvancedMarker] when a Map ID is configured
  /// and a legacy [Marker] otherwise. Keeping the two ends behind one builder
  /// stops the marker class and [_advancedMarkers] from drifting apart.
  Marker _pin({
    required String id,
    required LatLng position,
    required BitmapDescriptor icon,
    Offset anchor = const Offset(0.5, 1),
    String? label,
  }) {
    final markerId = MarkerId(id);
    final infoWindow = label == null
        ? InfoWindow.noText
        : InfoWindow(title: label);
    return _advancedMarkers
        ? AdvancedMarker(
            markerId: markerId,
            position: position,
            icon: icon,
            anchor: anchor,
            infoWindow: infoWindow,
          )
        : Marker(
            markerId: markerId,
            position: position,
            icon: icon,
            anchor: anchor,
            infoWindow: infoWindow,
          );
  }

  /// A dotted straight line joining the two ends. Not a driven route (no
  /// Directions call) — just a visual tie between origin and destination.
  Set<Polyline> _lines(Color color) => {
    Polyline(
      polylineId: const PolylineId('route'),
      points: [_toLatLng(widget.start), _toLatLng(widget.destination)],
      color: color,
      width: 4,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      patterns: [PatternItem.dot, PatternItem.gap(14)],
    ),
  };

  /// The box enclosing both ends, so the camera can frame the whole route.
  LatLngBounds get _bounds {
    final a = _toLatLng(widget.start);
    final b = _toLatLng(widget.destination);
    return LatLngBounds(
      southwest: LatLng(
        math.min(a.latitude, b.latitude),
        math.min(a.longitude, b.longitude),
      ),
      northeast: LatLng(
        math.max(a.latitude, b.latitude),
        math.max(a.longitude, b.longitude),
      ),
    );
  }

  /// Frames both markers with breathing room. Retried once post-layout: on the
  /// first `onMapCreated` the surface can still be zero-sized, which makes
  /// `newLatLngBounds` throw — the retry lands after the map has a size.
  Future<void> _frameRoute(GoogleMapController map) async {
    try {
      await map.moveCamera(CameraUpdate.newLatLngBounds(_bounds, 48));
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      try {
        await map.moveCamera(CameraUpdate.newLatLngBounds(_bounds, 48));
      } catch (_) {
        // Leave the camera at its initial midpoint; both pins are still shown.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(SarthiTheme.radius);
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: _mapsFailed
            ? _placeholder(const Icon(Icons.map_outlined))
            : !_mapsReady
            ? _placeholder(const CircularProgressIndicator())
            : GoogleMap(
                // Soft topographic base — a quieter backdrop for the route than
                // the default roadmap, and it sits with the Vast Quiet theme.
                mapType: MapType.terrain,
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    (widget.start.latitude + widget.destination.latitude) / 2,
                    (widget.start.longitude + widget.destination.longitude) / 2,
                  ),
                  zoom: 11,
                ),
                markers: _markers,
                // Advanced markers need a Map ID and a matching marker type;
                // both stay null/legacy until one is configured.
                markerType: _advancedMarkers
                    ? GoogleMapMarkerType.advancedMarker
                    : GoogleMapMarkerType.marker,
                mapId: _advancedMarkers ? GoogleMapsConfig.mapId : null,
                polylines: _lines(Theme.of(context).colorScheme.primary),
                // A static overview: no gestures, so the parent list scrolls
                // freely and the frame the camera picks is what the user sees.
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                onMapCreated: (map) {
                  _map = map;
                  _frameRoute(map);
                },
              ),
      ),
    );
  }

  /// Neutral fill shown while the SDK loads or when it fails — sized by the
  /// same aspect ratio so the layout never jumps.
  Widget _placeholder(Widget child) => ColoredBox(
    color: RideSurfaces.washOf(context),
    child: Center(child: child),
  );
}
