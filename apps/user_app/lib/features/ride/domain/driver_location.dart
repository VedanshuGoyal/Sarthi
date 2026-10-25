import 'geo_point.dart';

/// Where the assigned driver last was, as their app reported it — for the
/// live map on the ride details screen.
///
/// A pure domain type; [DriverLocation.tryParse] reads the backend's
/// `GET /me/bookings/{id}/driver-location` `location` object.
class DriverLocation {
  const DriverLocation({
    required this.point,
    required this.updatedAt,
    this.heading,
  });

  final GeoPoint point;

  /// Direction of travel in degrees (0 = north), when the phone knew it.
  final double? heading;

  /// When the driver's phone took this fix.
  final DateTime updatedAt;

  /// Parses one fix, or null for a missing (`"location": null`) or malformed
  /// one.
  static DriverLocation? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final updatedAt = json['updatedAt'] is String
        ? DateTime.tryParse(json['updatedAt'] as String)?.toLocal()
        : null;
    if (lat is! num || lng is! num || updatedAt == null) return null;
    return DriverLocation(
      point: GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble()),
      heading: (json['heading'] as num?)?.toDouble(),
      updatedAt: updatedAt,
    );
  }
}
