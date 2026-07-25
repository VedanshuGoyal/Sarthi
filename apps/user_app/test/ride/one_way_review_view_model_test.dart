import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/view_model/one_way_review_view_model.dart';

/// A repository whose only useful answer is a canned (or failing) drive time.
/// Records each requested departure so tests can check the chosen time is sent.
class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository({this.eta}) : super(tokenProvider: _token);

  /// The drive time to return; null makes the estimate fail.
  Duration? eta;

  /// Every `departureAt` the view model asked about, in order.
  final List<DateTime?> departures = [];

  static Future<String> _token() async => 'test';

  @override
  Future<Duration> travelTime({
    required GeoPoint start,
    required GeoPoint destination,
    DateTime? departureAt,
  }) async {
    departures.add(departureAt);
    final eta = this.eta;
    if (eta == null) throw const LocationException('no route');
    return eta;
  }
}

OneWayDraft _draft({DateTime? scheduledAt}) => (
  start: const PickupLocation(
    address: 'MG Road, Bengaluru',
    point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
  ),
  destination: const PickupLocation(
    address: 'Kempegowda International Airport, Bengaluru',
    point: GeoPoint(latitude: 13.1986, longitude: 77.7066),
  ),
  scheduledAt: scheduledAt ?? DateTime(2026, 7, 25, 10, 30),
  carType: CarType.sedan,
  transmission: Transmission.automatic,
);

void main() {
  group('OneWayReviewViewModel', () {
    test('a near-term start uses the cheap current-traffic estimate — one '
        'request, on entry', () async {
      final repo = _FakeLocationRepository(
        eta: const Duration(hours: 1, minutes: 25),
      );
      // Half an hour out sits inside the near-term window.
      final vm = OneWayReviewViewModel(
        draft: _draft(scheduledAt: DateTime(2026, 7, 25, 10, 30)),
        repository: repo,
        now: () => DateTime(2026, 7, 25, 10),
      );
      check(vm.isEstimatingTravelTime).isTrue();
      check(vm.travelTime).isNull();
      check(vm.canConfirm).isFalse();

      // Let the fake's future resolve.
      await Future<void>.delayed(Duration.zero);

      check(vm.isEstimatingTravelTime).isFalse();
      check(vm.travelTime).equals(const Duration(hours: 1, minutes: 25));
      // No departure passed — the repository takes the cheap Ola path.
      check(repo.departures).deepEquals([null]);
    });

    test('a far-out start asks for the time-aware estimate', () async {
      final repo = _FakeLocationRepository(eta: const Duration(hours: 2));
      final when = DateTime(2026, 7, 25, 18);
      final vm = OneWayReviewViewModel(
        draft: _draft(scheduledAt: when),
        repository: repo,
        now: () => DateTime(2026, 7, 25, 10),
      );
      await Future<void>.delayed(Duration.zero);

      check(vm.travelTime).equals(const Duration(hours: 2));
      check(repo.departures).deepEquals([when]);
    });

    test('the arrived estimate completes the trip', () async {
      final repo = _FakeLocationRepository(eta: const Duration(hours: 2));
      final when = DateTime(2026, 7, 30, 9, 30);
      final vm = OneWayReviewViewModel(
        draft: _draft(scheduledAt: when),
        repository: repo,
        now: () => DateTime(2026, 7, 25, 10),
      );
      await Future<void>.delayed(Duration.zero);

      check(vm.canConfirm).isTrue();
      final json = vm.trip!.toJson();
      check(json['scheduledAt']).equals('2026-07-30T09:30:00.000');
      check(json['estimatedTravelMinutes']).equals(120);
      check(json['carType']).equals('sedan');
      check(json['transmission']).equals('automatic');
    });

    test('a failed estimate blocks confirm and can be retried', () async {
      final repo = _FakeLocationRepository(eta: null);
      final vm = OneWayReviewViewModel(draft: _draft(), repository: repo);
      await Future<void>.delayed(Duration.zero);

      check(vm.isEstimatingTravelTime).isFalse();
      check(vm.travelTime).isNull();
      check(vm.estimateFailed).isTrue();
      check(vm.canConfirm).isFalse();
      check(vm.trip).isNull();

      repo.eta = const Duration(minutes: 50);
      vm.retryEstimate();
      check(vm.isEstimatingTravelTime).isTrue();
      await Future<void>.delayed(Duration.zero);

      check(vm.estimateFailed).isFalse();
      check(vm.travelTime).equals(const Duration(minutes: 50));
      check(vm.canConfirm).isTrue();
      check(vm.trip!.estimatedTravelTime).equals(const Duration(minutes: 50));
    });

    test('a seeded estimate makes no request and confirms at once', () {
      final repo = _FakeLocationRepository(eta: const Duration(minutes: 45));
      final vm = OneWayReviewViewModel(
        draft: _draft(),
        repository: repo,
        initialTravelTime: const Duration(minutes: 45),
      );
      check(repo.departures).isEmpty();
      check(vm.canConfirm).isTrue();
      check(vm.trip!.estimatedTravelTime).equals(const Duration(minutes: 45));
      check(vm.trip!.start.address).equals('MG Road, Bengaluru');
    });
  });
}
