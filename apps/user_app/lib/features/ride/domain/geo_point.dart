import 'dart:math' as math;

/// A latitude/longitude pair.
///
/// Pure domain: no map SDK or plugin type (Geolocator's `Position`, a maps
/// package's `LatLng`) leaks past the data layer — everything above speaks in
/// [GeoPoint], per the repository guideline.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// `"lat,lng"` — the form Ola Maps expects in query parameters.
  String toLatLngParam() => '$latitude,$longitude';

  /// Great-circle distance to [other] in metres (haversine).
  double distanceTo(GeoPoint other) {
    const earthRadiusMetres = 6371000.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLng = rad(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(other.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusMetres * math.asin(math.sqrt(a));
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
