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
    'customer': {'name': 'Asha Kumari', 'phoneE164': '+919800000000'},
  'distanceM': 700.0,
};

Ride ride({String id = 'r1', String status = 'requested'}) =>
    Ride.tryParse(rideJson(id: id, status: status))!;

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
  final List<bool> duty = [];

  @override
  Future<List<Ride>> requests({double? lat, double? lng}) async => openRides;

  @override
  Future<List<Ride>> myRides() async => mine;

  @override
  Future<Ride?> act(String id, RideAction action, {String? otp}) async {
    acted.add((id, action));
    if (action == RideAction.start) lastOtp = otp;
    final failure = failures[action];
    if (failure != null) throw failure;
    final status = switch (action) {
      RideAction.accept => 'accepted',
      RideAction.arrive => 'arrived',
      RideAction.start => 'in_progress',
      RideAction.complete => 'completed',
      _ => null,
    };
    if (status == null) return null;
    return Ride.tryParse(rideJson(id: id, status: status, withCustomer: true));
  }

  @override
  Future<Earnings> earnings() async => summary;

  @override
  Future<void> setDuty({required bool online, double? lat, double? lng}) async {
    duty.add(online);
  }
}

/// A [LocationService] that answers with a fixed position.
class FakeLocationService implements LocationService {
  const FakeLocationService([this.position = (lat: 28.63, lng: 77.21)]);

  final DevicePosition? position;

  @override
  Future<DevicePosition?> currentPosition({
    Duration timeout = const Duration(seconds: 8),
  }) async => position;

  @override
  Future<LocationPermissionResult> requestPermission() async =>
      LocationPermissionResult.granted;
}
