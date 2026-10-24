import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/one_way_trip.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/place_suggestion.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/one_way_route_screen.dart';
import 'package:user_app/features/ride/view_model/pickup_selection_view_model.dart';

import '../support/fake_location_repository.dart';

const _airport = PlaceSuggestion(
  placeId: 'p1',
  primaryText: 'IGI Airport',
  secondaryText: 'New Delhi',
  address: 'Indira Gandhi International Airport, New Delhi',
  point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
);

const _here = PickupLocation(
  address: 'My street, New Delhi',
  point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
);

const _home = PickupLocation(
  address: 'Home, Saket',
  point: GeoPoint(latitude: 28.5245, longitude: 77.2066),
  placeId: 'r1',
);

/// Pumps the route step with the destination search already showing the
/// airport, and captures the route it confirms.
class _Harness {
  _Harness(this.repo);

  final FakeLocationRepository repo;
  OneWayRoute? confirmed;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(repo),
          pickupSelectionViewModelProvider.overrideWith(
            (ref) => PickupSelectionViewModel(
              repository: ref.watch(locationRepositoryProvider),
              initialQuery: 'Airport',
              initialSuggestions: const [_airport],
            ),
          ),
        ],
        child: MaterialApp(
          home: OneWayRouteScreen(onConfirmed: (_, route) => confirmed = route),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('the start is pre-filled, so one tap on a destination '
      'completes the route', (tester) async {
    final harness = _Harness(FakeLocationRepository(current: _here));
    await harness.pump(tester);

    expect(find.text('My street, New Delhi'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);

    await tester.tap(find.text('IGI Airport'));
    await tester.pumpAndSettle();

    expect(harness.confirmed?.start, _here);
    expect(harness.confirmed?.destination.address, _airport.address);
  });

  testWidgets('without GPS, choosing a destination asks for the start first', (
    tester,
  ) async {
    final harness = _Harness(
      FakeLocationRepository(
        currentError: const LocationPermissionException('Allow location'),
        recents: const [_home],
      ),
    );
    await harness.pump(tester);

    expect(find.text('Choose a starting point'), findsOneWidget);

    await tester.tap(find.text('IGI Airport'));
    await tester.pumpAndSettle();

    // The starting-point picker opened with its own, empty search.
    expect(find.text('Set starting point'), findsOneWidget);
    expect(harness.confirmed, isNull);

    await tester.tap(find.text('Home, Saket'));
    await tester.pumpAndSettle();

    expect(harness.confirmed?.start, _home);
    expect(harness.confirmed?.destination.address, _airport.address);
  });

  testWidgets('the From row changes the start and keeps the destination '
      'search', (tester) async {
    final harness = _Harness(
      FakeLocationRepository(current: _here, recents: const [_home]),
    );
    await harness.pump(tester);

    await tester.tap(find.text('My street, New Delhi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home, Saket'));
    await tester.pumpAndSettle();

    // Back on the route step: new start, destination results untouched.
    expect(find.text('Home, Saket'), findsOneWidget);
    expect(find.text('Starting point · tap to change'), findsOneWidget);
    expect(find.text('IGI Airport'), findsOneWidget);
    expect(harness.confirmed, isNull);
  });
}
