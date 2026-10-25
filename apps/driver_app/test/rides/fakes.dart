import 'dart:async';

import 'package:driver_app/core/services/location_service.dart';
import 'package:driver_app/features/rides/data/rides_repository.dart';
import 'package:driver_app/features/rides/domain/ride.dart';

/// A ride as the backend sends it, with overridable fields.
Map<String, dynamic> rideJson({
  String id = 'r1',
  String tripType = 'roundTrip',
  String status = 'requested',
  String scheduledAt = '2026-10-26T09:00:00+05:30',
  int farePaise = 34000,
  bool withCustomer = false,
  double? customerRating,
  int customerRatingCount = 0,
  String? cancelledAt,
  String? cancelledBy,
  String? cancelReason,
  Map<String, dynamic>? myRating,
}) => {
  'id': id,
  'tripType': tripType,
  'status': status,
  'scheduledAt': scheduledAt,
  'endsAt': '2026-10-26T12:00:00+05:30',
  'farePaise': farePaise,
  'fareEstimated': false,
  'pickup': {
    'address': 'Connaught Place, New Delhi',
    'lat': 28.63,
    'lng': 77.21,
  },
  'hours': 3,
  'car': {
    'registration': 'DL01AB1234',
    'carType': 'sedan',
    'transmission': 'automatic',
  },
  if (withCustomer)
    'customer': {
      'name': 'Asha Kumari',
      'phoneE164': '+919800000000',
      if (customerRating != null) 'rating': customerRating,
      'ratingCount': customerRatingCount,
    },
  'distanceM': 700.0,
  if (cancelledAt != null) 'cancelledAt': cancelledAt,
  if (cancelledBy != null) 'cancelledBy': cancelledBy,
  if (cancelReason != null) 'cancelReason': cancelReason,
  if (myRating != null) 'myRating': myRating,
};

Ride ride({
  String id = 'r1',
  String status = 'requested',
  String scheduledAt = '2026-10-26T09:00:00+05:30',
  String? cancelledAt,
  String? cancelledBy,
  String? cancelReason,
  Map<String, dynamic>? myRating,
}) => Ride.tryParse(
  rideJson(
    id: id,
    status: status,
    scheduledAt: scheduledAt,
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancelReason: cancelReason,
    myRating: myRating,
  ),
)!;

/// An in-memory [RidesRepository] that records calls and plays back canned
/// answers.
class FakeRidesRepository implements RidesRepository {
  List<Ride> openRides = [];
  List<Ride> mine = [];
  Earnings summary = const Earnings();

  /// When set, [act] throws this for the given action.
  Map<RideAction, RidesException> failures = {};

  final List<(String, RideAction)> acted = [];

  /// The code sent with the last start.
  String? lastOtp;

  /// The stars/note sent with the last rating.
  (int, String?)? lastRating;
  final List<bool> duty = [];

  /// Every `(lat, lng, heading)` sent to [shareLocation].
  final List<(double, double, double?)> sharedLocations = [];

  /// When true, [shareLocation] throws instead of recording.
  bool failShareLocation = false;

  @override
  Future<List<Ride>> requests({double? lat, double? lng}) async => openRides;

  @override
  Future<List<Ride>> myRides() async => mine;

  @override
  Future<Ride?> act(
    String id,
    RideAction action, {
    String? otp,
    int? stars,
    String? note,
  }) async {
    acted.add((id, action));
    if (action == RideAction.start) lastOtp = otp;
    if (action == RideAction.rate) lastRating = (stars ?? 0, note);
    final failure = failures[action];
    if (failure != null) throw failure;
    final status = switch (action) {
      RideAction.accept => 'accepted',
      RideAction.arrive => 'arrived',
      RideAction.start => 'in_progress',
      RideAction.complete => 'completed',
      RideAction.rate => 'completed',
      _ => null,
    };
    if (status == null) return null;
    return Ride.tryParse(
      rideJson(
        id: id,
        status: status,
        withCustomer: true,
        myRating: action == RideAction.rate
            ? {'stars': stars ?? 0, if (note != null) 'note': note}
            : null,
      ),
    );
  }

  @override
  Future<Earnings> earnings() async => summary;

  @override
  Future<void> setDuty({required bool online, double? lat, double? lng}) async {
    duty.add(online);
  }

  @override
  Future<void> shareLocation({
    required double lat,
    required double lng,
    double? heading,
  }) async {
    if (failShareLocation) throw const RidesException('boom');
    sharedLocations.add((lat, lng, heading));
  }
}

/// A [LocationService] that answers with a fixed position, and whose
/// position stream is driven by the test via [emit].
class FakeLocationService implements LocationService {
  FakeLocationService([this.position = (lat: 28.63, lng: 77.21)]);

  final DevicePosition? position;
  final _controller = StreamController<DeviceFix>.broadcast();

  @override
  Future<DevicePosition?> currentPosition({
    Duration timeout = const Duration(seconds: 8),
  }) async => position;

  @override
  Future<LocationPermissionResult> requestPermission() async =>
      LocationPermissionResult.granted;

  @override
  Stream<DeviceFix> positionStream() => _controller.stream;

  /// Pushes a fix to anything listening to [positionStream].
  void emit(DeviceFix fix) => _controller.add(fix);
}
