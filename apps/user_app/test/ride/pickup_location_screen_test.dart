import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/place_suggestion.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/pickup_location_screen.dart';
import 'package:user_app/features/ride/view_model/pickup_selection_view_model.dart';

import '../support/fake_location_repository.dart';

const _suggestion = PlaceSuggestion(
  placeId: 'p1',
  primaryText: 'MG Road',
  secondaryText: 'Bengaluru',
  address: 'MG Road, Bengaluru',
  point: GeoPoint(latitude: 12.97, longitude: 77.6),
);

/// Pumps the screen with the view model seeded into the given state and
/// captures whatever the screen confirms.
class _Harness {
  PickupLocation? confirmed;
  final FakeLocationRepository repo;

  _Harness({List<PickupLocation> recents = const []})
    : repo = FakeLocationRepository(recents: recents);

  Future<void> pump(
    WidgetTester tester, {
    List<PlaceSuggestion> suggestions = const [],
    String query = '',
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(repo),
          pickupSelectionViewModelProvider.overrideWith(
            (ref) => PickupSelectionViewModel(
              repository: ref.watch(locationRepositoryProvider),
              initialQuery: query,
              initialSuggestions: suggestions,
            ),
          ),
        ],
        child: MaterialApp(
          home: PickupLocationScreen(
            onConfirmed: (_, pickup) => confirmed = pickup,
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('renders results with no separate confirm button', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester, suggestions: const [_suggestion], query: 'MG');

    expect(find.text('MG Road'), findsOneWidget);
    // Tap-and-go: choosing a result is the confirmation.
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('tapping a suggestion confirms it immediately', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, suggestions: const [_suggestion], query: 'MG');

    await tester.tap(find.text('MG Road'));
    await tester.pumpAndSettle();

    expect(harness.confirmed, isNotNull);
    expect(harness.confirmed!.address, 'MG Road, Bengaluru');
    // The choice was also persisted to recents on the way out.
    expect(harness.repo.remembered.map((p) => p.address), [
      'MG Road, Bengaluru',
    ]);
  });

  testWidgets('tapping a recent confirms it immediately', (tester) async {
    const recent = PickupLocation(
      address: 'Home, Koramangala',
      point: GeoPoint(latitude: 12.93, longitude: 77.62),
      placeId: 'r1',
    );
    final harness = _Harness(recents: const [recent]);
    await harness.pump(tester);
    // Let the async recents load settle and rebuild.
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);

    await tester.tap(find.text('Home, Koramangala'));
    await tester.pumpAndSettle();

    expect(harness.confirmed, isNotNull);
    expect(harness.confirmed!.address, 'Home, Koramangala');
  });

  testWidgets('using the current location confirms once GPS resolves', (
    tester,
  ) async {
    final harness = _Harness();
    harness.repo.current = const PickupLocation(
      address: 'My street, Bengaluru',
      point: GeoPoint(latitude: 12.9, longitude: 77.6),
    );
    await harness.pump(tester);

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(harness.confirmed, isNotNull);
    expect(harness.confirmed!.address, 'My street, Bengaluru');
  });
}
