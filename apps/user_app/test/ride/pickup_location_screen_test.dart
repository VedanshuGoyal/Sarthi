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
  primaryText: 'Connaught Place',
  secondaryText: 'New Delhi',
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
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
    await harness.pump(tester, suggestions: const [_suggestion], query: 'Connaught');

    expect(find.text('Connaught Place'), findsOneWidget);
    // Tap-and-go: choosing a result is the confirmation.
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('tapping a suggestion confirms it immediately', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, suggestions: const [_suggestion], query: 'Connaught');

    await tester.tap(find.text('Connaught Place'));
    await tester.pumpAndSettle();

    expect(harness.confirmed, isNotNull);
    expect(harness.confirmed!.address, 'Connaught Place, New Delhi');
    // The choice was also persisted to recents on the way out.
    expect(harness.repo.remembered.map((p) => p.address), [
      'Connaught Place, New Delhi',
    ]);
  });

  testWidgets('tapping a recent confirms it immediately', (tester) async {
    const recent = PickupLocation(
      address: 'Home, Saket',
      point: GeoPoint(latitude: 28.5355, longitude: 77.3910),
      placeId: 'r1',
    );
    final harness = _Harness(recents: const [recent]);
    await harness.pump(tester);
    // Let the async recents load settle and rebuild.
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);

    await tester.tap(find.text('Home, Saket'));
    await tester.pumpAndSettle();

    expect(harness.confirmed, isNotNull);
    expect(harness.confirmed!.address, 'Home, Saket');
  });

  testWidgets('using the current location confirms once GPS resolves', (
    tester,
  ) async {
    final harness = _Harness();
    harness.repo.current = const PickupLocation(
      address: 'My street, New Delhi',
      point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
    );
    await harness.pump(tester);

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(harness.confirmed, isNotNull);
    expect(harness.confirmed!.address, 'My street, New Delhi');
  });
}
