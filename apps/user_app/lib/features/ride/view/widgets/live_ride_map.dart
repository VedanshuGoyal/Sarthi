import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../core/config/google_maps_config.dart';
import '../../../../core/maps/web_maps_loader.dart';
import '../../domain/geo_point.dart';

/// A small live map of the pickup and the driver's latest position, framed
/// so both are in view and re-framed as the driver moves.
///
/// Renders only — points in, a map out. Without a Maps key in this build, or
/// when the SDK fails to load, it renders nothing, and the screen's text line
/// ("Ravi is 2.3 km away") carries the information on its own. Gestures are
/// off so it never fights the surrounding scroll view.
class LiveRideMap extends StatefulWidget {
  const LiveRideMap({
    super.key,
    required this.pickup,
    required this.driver,
    this.heading,
  });

  final GeoPoint? pickup;
  final GeoPoint? driver;

  /// The driver's direction of travel (0 = north), turning their marker.
  final double? heading;

  /// Whether a map can be shown at all in this build.
  static bool get isAvailable => GoogleMapsConfig.isConfigured;

  @override
  State<LiveRideMap> createState() => _LiveRideMapState();
}

class _LiveRideMapState extends State<LiveRideMap> {
  GoogleMapController? _map;
  bool _mapsReady = false;
  bool _mapsFailed = false;
  BitmapDescriptor? _driverIcon;
  bool _iconRequested = false;

  static LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  void initState() {
    super.initState();
    _loadMapsSdk();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iconRequested) {
      _iconRequested = true;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final t = SkylineTokens.of(context);
      _drawDriverIcon(dpr, t.signal, t.surface).then((icon) {
        if (mounted) setState(() => _driverIcon = icon);
      });
    }
  }

  @override
  void didUpdateWidget(LiveRideMap old) {
    super.didUpdateWidget(old);
    if (old.driver != widget.driver || old.pickup != widget.pickup) {
      final map = _map;
      if (map != null) _frame(map);
    }
  }

  Future<void> _loadMapsSdk() async {
    // No Maps key in this build: render nothing rather than a blank map.
    if (!LiveRideMap.isAvailable) {
      _mapsFailed = true;
      return;
    }
    try {
      await ensureWebMapsReady();
      if (mounted) setState(() => _mapsReady = true);
    } catch (_) {
      if (mounted) setState(() => _mapsFailed = true);
    }
  }

  /// The driver's marker: a signal-blue disc with a white rim and an arrow
  /// pointing the way they face.
  static Future<BitmapDescriptor> _drawDriverIcon(
    double dpr,
    Color fill,
    Color rim,
  ) async {
    final size = 40 * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final centre = Offset(size / 2, size / 2);
    canvas
      ..drawCircle(centre, size / 2, Paint()..color = rim)
      ..drawCircle(centre, size / 2 - 3 * dpr, Paint()..color = fill);
    final arrow = Path()
      ..moveTo(centre.dx, centre.dy - 10 * dpr)
      ..lineTo(centre.dx + 7 * dpr, centre.dy + 8 * dpr)
      ..lineTo(centre.dx, centre.dy + 4 * dpr)
      ..lineTo(centre.dx - 7 * dpr, centre.dy + 8 * dpr)
      ..close();
    canvas.drawPath(arrow, Paint()..color = rim);
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: dpr,
    );
  }

  Set<Marker> get _markers => {
    if (widget.pickup case final pickup?)
      Marker(
        markerId: const MarkerId('pickup'),
        position: _toLatLng(pickup),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
    if (widget.driver case final driver?)
      Marker(
        markerId: const MarkerId('driver'),
        position: _toLatLng(driver),
        icon:
            _driverIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: widget.heading ?? 0,
        infoWindow: const InfoWindow(title: 'Your driver'),
      ),
  };

  List<GeoPoint> get _points => [?widget.pickup, ?widget.driver];

  /// Frames every point with breathing room, or centres on a lone one.
  /// Retried once: the first frame can land before the map has a size.
  Future<void> _frame(GoogleMapController map) async {
    final points = _points;
    if (points.isEmpty) return;
    final CameraUpdate update;
    if (points.length == 1 || points[0].distanceTo(points[1]) < 50) {
      update = CameraUpdate.newLatLngZoom(_toLatLng(points.first), 15);
    } else {
      update = CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            points.map((p) => p.latitude).reduce(math.min),
            points.map((p) => p.longitude).reduce(math.min),
          ),
          northeast: LatLng(
            points.map((p) => p.latitude).reduce(math.max),
            points.map((p) => p.longitude).reduce(math.max),
          ),
        ),
        56,
      );
    }
    try {
      await map.animateCamera(update);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      try {
        await map.moveCamera(update);
      } catch (_) {
        // Keep the opening camera; the markers still show.
      }
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    if (_mapsFailed || points.isEmpty) return const SizedBox.shrink();
    final t = SkylineTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Skyline.radius),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: !_mapsReady
            ? ColoredBox(
                color: t.sunken,
                child: const Center(child: CircularProgressIndicator()),
              )
            : GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _toLatLng(points.first),
                  zoom: 14,
                ),
                markers: _markers,
                markerType: GoogleMapMarkerType.marker,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                onMapCreated: (map) {
                  _map = map;
                  _frame(map);
                },
              ),
      ),
    );
  }
}
