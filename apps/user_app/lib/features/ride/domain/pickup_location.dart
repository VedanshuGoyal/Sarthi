import 'geo_point.dart';

/// A confirmed pickup point: a human-readable [address] and its [point].
///
/// The output of the pickup step and the input the booking flow will build on.
class PickupLocation {
  const PickupLocation({
    required this.address,
    required this.point,
    this.placeId,
  });

  final String address;
  final GeoPoint point;

  /// Ola place id when the pickup came from a search result; null when it was
  /// reverse-geocoded from raw GPS coordinates.
  final String? placeId;

  Map<String, dynamic> toJson() => {
    'address': address,
    'point': point.toJson(),
    if (placeId != null) 'placeId': placeId,
  };

  factory PickupLocation.fromJson(Map<String, dynamic> json) => PickupLocation(
    address: json['address'] as String,
    point: GeoPoint.fromJson(json['point'] as Map<String, dynamic>),
    placeId: json['placeId'] as String?,
  );
}
