import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
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

/// Pumps the screen with the view model seeded into [start] state.
Future<PickupLocation?> _pumpScreen(
  WidgetTester tester, {
  List<PlaceSuggestion> suggestions = const [],
  PickupLocation? selected,
  String query = '',
  List<PickupLocation> recents = const [],
}) async {
  PickupLocation? confirmed;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationRepositoryProvider.overrideWithValue(
          FakeLocationRepository(recents: recents),
        ),
        pickupSelectionViewModelProvider.overrideWith(
          (ref) => PickupSelectionViewModel(
            repository: ref.watch(locationRepositoryProvider),
            initialQuery: query,
            initialSuggestions: suggestions,
            initialSelected: selected,
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
  return confirmed;
}

void main() {
  testWidgets('confirm is disabled until a pickup is chosen', (tester) async {
    await _pumpScreen(tester, suggestions: const [_suggestion], query: 'MG');

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('MG Road'), findsOneWidget);
  });

  testWidgets('tapping a suggestion selects it and enables confirm', (
    tester,
  ) async {
    await _pumpScreen(tester, suggestions: const [_suggestion], query: 'MG');

    await tester.tap(find.text('MG Road'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('shows recent pickups when the field is empty', (tester) async {
    await _pumpScreen(
      tester,
      recents: const [
        PickupLocation(
          address: 'Home, Koramangala',
          point: GeoPoint(latitude: 12.93, longitude: 77.62),
          placeId: 'r1',
        ),
      ],
    );
    // Let the async recents load settle and rebuild.
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Home, Koramangala'), findsOneWidget);

    // Confirm stays disabled until one is picked.
    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Home, Koramangala'));
    await tester.pumpAndSettle();

    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('confirming returns the chosen pickup', (tester) async {
    PickupLocation? confirmed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(
            FakeLocationRepository(),
          ),
          pickupSelectionViewModelProvider.overrideWith(
            (ref) => PickupSelectionViewModel(
              repository: ref.watch(locationRepositoryProvider),
              initialQuery: _suggestion.address,
              initialSelected: const PickupLocation(
                address: 'MG Road, Bengaluru',
                point: GeoPoint(latitude: 12.97, longitude: 77.6),
                placeId: 'p1',
              ),
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

    await tester.tap(find.widgetWithText(SarthiPrimaryButton, 'Confirm pickup'));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.address, 'MG Road, Bengaluru');
  });
}
