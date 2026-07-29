import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../core/config/google_maps_config.dart';
import '../../../../core/maps/web_maps_loader.dart';
import '../../../../core/theme/deep_signal/deep_signal.dart';
import '../../domain/geo_point.dart';

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

  String? _mapStyle;
  bool _styleRequested = false;

  static const _originAsset = 'assets/markers/pin_origin.png';
  static const _destinationAsset = 'assets/markers/pin_destination.png';
  static const _mapStyleAsset = 'assets/map_styles/soft_map_style.json';

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
    if (!_styleRequested) {
      _styleRequested = true;
      DefaultAssetBundle.of(context).loadString(_mapStyleAsset).then((style) {
        if (mounted) {
          setState(() {
            _mapStyle = style;
            _map?.setMapStyle(_mapStyle);
          });
        }
      }).catchError((e) {
        debugPrint('Failed to load map style: $e');
      });
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

  Future<BitmapDescriptor> _createPinMarker(Color color, {double devicePixelRatio = 1.0}) async {
    final double width = 36 * devicePixelRatio;
    final double height = 48 * devicePixelRatio;
    
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint stickPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5 * devicePixelRatio
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
      
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.fill;
      
    final Paint ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
      
    final Paint whiteFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
      
    // 1. Draw the small shadow dot at the very bottom
    final Offset groundPoint = Offset(width / 2, height - (2 * devicePixelRatio));
    canvas.drawOval(Rect.fromCenter(center: groundPoint, width: 8 * devicePixelRatio, height: 4 * devicePixelRatio), shadowPaint);
    
    // 2. Draw the vertical stick (from center of head to ground point)
    final Offset circleCenter = Offset(width / 2, width / 2);
    canvas.drawLine(
      circleCenter,
      groundPoint,
      stickPaint,
    );

    // 3. Draw the circular head
    // Outer colored ring
    canvas.drawCircle(circleCenter, 12.0 * devicePixelRatio, ringPaint);
    // Inner white circle
    canvas.drawCircle(circleCenter, 8.0 * devicePixelRatio, whiteFill);
    // Center colored dot
    canvas.drawCircle(circleCenter, 3.5 * devicePixelRatio, ringPaint);

    final ui.Image image = await pictureRecorder.endRecording().toImage(width.toInt(), height.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Programmatically draws minimal UI markers matching the requested style.
  Future<void> _loadMarkerIcons(ImageConfiguration config) async {
    final dpr = config.devicePixelRatio ?? 2.0;
    
    final start = await _createPinMarker(const Color(0xFF1B8754), devicePixelRatio: dpr); // Rapido Green
    final dest = await _createPinMarker(const Color(0xFFE2433B), devicePixelRatio: dpr); // Rapido Red
    
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
      anchor: const Offset(0.5, 1.0),
      label: widget.startLabel,
    ),
    _pin(
      id: 'destination',
      position: _toLatLng(widget.destination),
      icon:
          _destIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      anchor: const Offset(0.5, 1.0),
      label: widget.destinationLabel,
    ),
  };

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
    return Marker(
      markerId: markerId,
      position: position,
      icon: icon,
      anchor: anchor,
      infoWindow: infoWindow,
    );
  }

  /// A dashed straight line joining the two ends. Not a driven route (no
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
      patterns: [PatternItem.dash(16), PatternItem.gap(12)],
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
    final tokens = DeepSignalTokens.of(context);
    final radius = BorderRadius.circular(DeepSignalTokens.radius);
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: _mapsFailed
            ? _placeholder(const Icon(Icons.map_outlined))
            : !_mapsReady
            ? _placeholder(const CircularProgressIndicator())
            : GoogleMap(
                // Base map type — normal works best with JSON styling.
                mapType: MapType.normal,
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    (widget.start.latitude + widget.destination.latitude) / 2,
                    (widget.start.longitude + widget.destination.longitude) / 2,
                  ),
                  zoom: 11,
                ),
                markers: _markers,
                // Force legacy markers so the SDK accepts our local JSON styling
                markerType: GoogleMapMarkerType.marker,
                mapId: null,
                polylines: _lines(tokens.accent),
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
                  if (_mapStyle != null) {
                    map.setMapStyle(_mapStyle);
                  }
                  _frameRoute(map);
                },
              ),
      ),
    );
  }

  /// Neutral fill shown while the SDK loads or when it fails — sized by the
  /// same aspect ratio so the layout never jumps.
  Widget _placeholder(Widget child) => ColoredBox(
    color: DeepSignalTokens.of(context).skeleton,
    child: Center(child: child),
  );
}
