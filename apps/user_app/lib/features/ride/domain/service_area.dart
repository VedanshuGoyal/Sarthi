import 'geo_point.dart';

/// The geographic area Sarthi currently serves: Delhi NCR — Delhi itself and
/// the adjoining cities of Gurugram, Faridabad, Noida, Greater Noida and
/// Ghaziabad, plus nearby areas. Every pickup, drop and stop must fall inside
/// it; anything outside is refused with [outsideMessage] until we expand.
///
/// Modelled as a lat/lng bounding box — coarser than the real NCR outline but
/// trivial to reason about and to widen. When the served area grows, stretch
/// the bounds (or swap the box for a polygon) here; every caller reads through
/// [contains], so the boundary lives in exactly one place.
abstract final class ServiceArea {
  // A generous box around the NCR core. Covers Delhi, Gurugram, Faridabad,
  // Noida, Greater Noida and Ghaziabad with margin for their outskirts.
  static const double _minLat = 28.20;
  static const double _maxLat = 28.95;
  static const double _minLng = 76.75;
  static const double _maxLng = 77.9;

  /// Roughly central Delhi (Connaught Place). Biases place search toward the
  /// served area and centres the map picker before a device fix arrives.
  static const GeoPoint center = GeoPoint(
    latitude: 28.6139,
    longitude: 77.2090,
  );

  /// User-facing copy shown when a chosen place lies outside the served area.
  /// Safe to surface directly in the UI.
  static const String outsideMessage =
      "We're only serving Delhi NCR (Delhi, Gurugram, Faridabad, Noida and "
      'nearby areas) right now — pick a location within this area.';

  /// Whether [point] falls inside the served area.
  static bool contains(GeoPoint point) =>
      point.latitude >= _minLat &&
      point.latitude <= _maxLat &&
      point.longitude >= _minLng &&
      point.longitude <= _maxLng;
}
