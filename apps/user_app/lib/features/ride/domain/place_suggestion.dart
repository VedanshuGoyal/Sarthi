import 'geo_point.dart';

/// One row in the pickup search results — a place the customer might pick.
///
/// Modelled on an Ola Maps autocomplete *prediction*: [primaryText] is the
/// place name and [secondaryText] its context (city/area) for a two-line row,
/// while [address] is the full description used once it becomes the pickup.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.address,
    this.point,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String address;

  /// Coordinates when the prediction carried them (Ola includes `geometry`);
  /// null means the repository must resolve them before confirming.
  final GeoPoint? point;

  /// Parses one entry from Ola Maps `/places/v1/autocomplete` `predictions[]`.
  factory PlaceSuggestion.fromOlaPrediction(Map<String, dynamic> json) {
    final structured = json['structured_formatting'];
    final formatting = structured is Map<String, dynamic> ? structured : const {};
    final description = json['description'] as String? ?? '';
    final main = formatting['main_text'] as String? ?? description;
    final secondary = formatting['secondary_text'] as String? ?? '';

    return PlaceSuggestion(
      placeId: json['place_id'] as String? ?? '',
      primaryText: main,
      secondaryText: secondary,
      address: description.isNotEmpty ? description : main,
      point: _pointOf(json['geometry']),
    );
  }

  /// Extracts `geometry.location.{lat,lng}` when present.
  static GeoPoint? _pointOf(Object? geometry) {
    if (geometry is! Map<String, dynamic>) return null;
    final location = geometry['location'];
    if (location is! Map<String, dynamic>) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return GeoPoint(latitude: lat, longitude: lng);
  }
}
