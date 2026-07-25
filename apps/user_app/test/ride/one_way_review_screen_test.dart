import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/one_way_review_screen.dart';
import 'package:user_app/features/ride/view_model/one_way_review_view_model.dart';

/// A repository answering every drive-time request with a settable [eta]
/// (null fails the request), so retry can be exercised from the UI.
class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository({this.eta}) : super(tokenProvider: _token);

  Duration? eta;
  int requests = 0;

  static Future<String> _token() async => 'test';

  @override
  Future<Duration> travelTime({
    required GeoPoint start,
    required GeoPoint destination,
    DateTime? departureAt,
  }) async {
    requests++;
    final eta = this.eta;
    if (eta == null) throw const LocationException('no route');
    return eta;
  }
}

final _draft = (
  start: const PickupLocation(
    address: 'MG Road, Bengaluru',
    point: GeoPoint(latitude: 12.9756, longitude: 77.6068),
  ),
  destination: const PickupLocation(
    address: 'Kempegowda International Airport, Bengaluru',
    point: GeoPoint(latitude: 13.1986, longitude: 77.7066),
  ),
  scheduledAt: DateTime(2026, 7, 20, 9, 30),
  carType: CarType.sedan,
  transmission: Transmission.manual,
);

/// Pumps the review screen with the view model seeded to [travelTime], or
/// backed by [repository] when the estimate flow itself is under test.
Future<void> _pump(
  WidgetTester tester, {
  Duration? travelTime,
  LocationRepository? repository,
  ValueChanged<OneWayTrip>? onOk,
}) {
  // A tall surface so the whole form is laid out at once.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        oneWayReviewViewModelProvider.overrideWith(
          (ref, draft) => OneWayReviewViewModel(
            draft: draft,
            repository: repository,
            initialTravelTime: travelTime,
          ),
        ),
      ],
      child: MaterialApp(
        home: OneWayReviewScreen(
          draft: _draft,
          onConfirmed: onOk == null ? null : (_, trip) => onOk(trip),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('echoes the settled plan and confirms with the estimate', (
    tester,
  ) async {
    OneWayTrip? received;
    await _pump(
      tester,
      travelTime: const Duration(hours: 1, minutes: 25),
      onOk: (t) => received = t,
    );

    expect(find.text('MG Road, Bengaluru'), findsOneWidget);
    expect(
      find.text('Kempegowda International Airport, Bengaluru'),
      findsOneWidget,
    );
    // The settled choices are echoed read-only — no pickers or dropdowns.
    expect(find.text('Sedan · Manual'), findsOneWidget);
    expect(find.byType(DropdownMenu), findsNothing);
    expect(find.text('About 1 h 25 min'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SarthiPrimaryButton, 'Confirm booking'),
    );
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.scheduledAt, DateTime(2026, 7, 20, 9, 30));
    expect(received!.carType, CarType.sedan);
    expect(received!.transmission, Transmission.manual);
    expect(received!.estimatedTravelTime, const Duration(hours: 1, minutes: 25));
  });

  testWidgets('shows progress while the estimate is fetched and blocks '
      'confirm', (tester) async {
    final repo = _FakeLocationRepository(eta: const Duration(minutes: 50));
    await _pump(tester, repository: repo);

    expect(find.text('Checking the drive time…'), findsOneWidget);
    expect(find.text('Checking the trip time…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.pump(); // let the fake's future resolve
    expect(find.text('About 50 min'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a failed estimate blocks confirm and retry re-asks', (
    tester,
  ) async {
    final repo = _FakeLocationRepository();
    await _pump(tester, repository: repo);
    await tester.pump(); // let the failing future resolve

    expect(find.text("Couldn't get the trip time."), findsOneWidget);
    expect(
      find.text('The trip time is needed to book — retry the estimate above.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    repo.eta = const Duration(minutes: 50);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(repo.requests, 2);
    expect(find.text('About 50 min'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
