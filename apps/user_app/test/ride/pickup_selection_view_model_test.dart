import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/place_suggestion.dart';
import 'package:user_app/features/ride/domain/service_area.dart';
import 'package:user_app/features/ride/view_model/pickup_selection_view_model.dart';

import '../support/fake_location_repository.dart';

const _suggestion = PlaceSuggestion(
  placeId: 'p1',
  primaryText: 'Connaught Place',
  secondaryText: 'New Delhi',
  address: 'Connaught Place, New Delhi',
  point: GeoPoint(latitude: 28.6315, longitude: 77.2167),
);

/// A place well outside the Delhi-NCR service area (Bengaluru), for the
/// refusal path.
const _outsideSuggestion = PlaceSuggestion(
  placeId: 'p2',
  primaryText: 'MG Road',
  secondaryText: 'Bengaluru',
  address: 'MG Road, Bengaluru',
  point: GeoPoint(latitude: 12.97, longitude: 77.6),
);

void main() {
  group('PickupSelectionViewModel', () {
    test('starts empty with nothing selected', () {
      final vm = PickupSelectionViewModel(repository: FakeLocationRepository());
      check(vm.query).isEmpty();
      check(vm.suggestions).isEmpty();
      check(vm.selected).isNull();
    });

    test('a long-enough query searches after the debounce', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository(suggestions: const [_suggestion]);
        final vm = PickupSelectionViewModel(repository: repo);

        vm.onQueryChanged('MG Road');
        // Marked searching immediately, but not yet dispatched.
        check(vm.isSearching).isTrue();
        check(repo.queries).isEmpty();

        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        check(repo.queries).deepEquals(['MG Road']);
        check(vm.suggestions).deepEquals(const [_suggestion]);
        check(vm.isSearching).isFalse();
      });
    });

    test('a too-short query clears results without calling the repository', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository(suggestions: const [_suggestion]);
        final vm = PickupSelectionViewModel(repository: repo);

        vm.onQueryChanged('MG');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        check(vm.suggestions).isEmpty();
        check(vm.isSearching).isFalse();
        check(repo.queries).isEmpty();
      });
    });

    test('only the latest keystroke wins when typing quickly', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository(suggestions: const [_suggestion]);
        final vm = PickupSelectionViewModel(repository: repo);

        vm.onQueryChanged('MG');
        vm.onQueryChanged('MG R');
        vm.onQueryChanged('MG Road');
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // The two earlier queries were debounced away; only the last fired.
        check(repo.queries).deepEquals(['MG Road']);
      });
    });

    test('selecting a suggestion returns the resolved pickup', () {
      final vm = PickupSelectionViewModel(repository: FakeLocationRepository());

      final pickup = vm.selectSuggestion(_suggestion);

      check(pickup?.address).equals('Connaught Place, New Delhi');
      check(pickup?.placeId).equals('p1');
      check(vm.selected).equals(pickup);
      check(vm.query).equals('Connaught Place, New Delhi');
      check(vm.suggestions).isEmpty();
    });

    test('a suggestion outside the service area is refused', () {
      final vm = PickupSelectionViewModel(repository: FakeLocationRepository());

      final pickup = vm.selectSuggestion(_outsideSuggestion);

      check(pickup).isNull();
      check(vm.selected).isNull();
      check(vm.error).equals(ServiceArea.outsideMessage);
    });

    test('editing the query after selecting clears the selection', () {
      final vm = PickupSelectionViewModel(repository: FakeLocationRepository());
      vm.selectSuggestion(_suggestion);
      check(vm.selected).isNotNull();

      vm.onQueryChanged('somewhere else');
      check(vm.selected).isNull();
    });

    test(
      'a suggestion with no coordinates surfaces an error, not a pickup',
      () {
        final vm = PickupSelectionViewModel(
          repository: FakeLocationRepository(),
        );

        final pickup = vm.selectSuggestion(
          const PlaceSuggestion(
            placeId: 'x',
            primaryText: 'Nowhere',
            secondaryText: '',
            address: 'Nowhere',
          ),
        );

        check(pickup).isNull();
        check(vm.selected).isNull();
        check(vm.error).isNotNull();
      },
    );

    test('current location fills the pickup from GPS', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository(
          current: const PickupLocation(
            address: 'My street, New Delhi',
            point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
          ),
        );
        final vm = PickupSelectionViewModel(repository: repo);

        PickupLocation? pickup;
        vm.useCurrentLocation().then((p) => pickup = p);
        check(vm.isLocating).isTrue();

        async.flushMicrotasks();

        check(vm.isLocating).isFalse();
        check(pickup?.address).equals('My street, New Delhi');
        check(vm.query).equals('My street, New Delhi');
      });
    });

    test('loads recents from the repository on construction', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository(
          recents: const [
            PickupLocation(
              address: 'Home, New Delhi',
              point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
              placeId: 'r1',
            ),
          ],
        );
        final vm = PickupSelectionViewModel(repository: repo);

        async.flushMicrotasks();

        check(vm.recents).length.equals(1);
        check(vm.recents.single.address).equals('Home, New Delhi');
      });
    });

    test('selecting a recent sets the pickup with no autocomplete call', () {
      final repo = FakeLocationRepository();
      final vm = PickupSelectionViewModel(repository: repo);

      const recent = PickupLocation(
        address: 'Home, New Delhi',
        point: GeoPoint(latitude: 28.6139, longitude: 77.2090),
        placeId: 'r1',
      );
      final pickup = vm.selectRecent(recent);

      check(pickup).equals(recent);
      check(vm.selected?.address).equals('Home, New Delhi');
      check(vm.query).equals('Home, New Delhi');
      check(repo.queries).isEmpty();
    });

    test('rememberSelected persists the chosen pickup', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository();
        final vm = PickupSelectionViewModel(repository: repo);

        vm.selectSuggestion(_suggestion);
        vm.rememberSelected();
        async.flushMicrotasks();

        check(
          repo.remembered.map((p) => p.address).toList(),
        ).deepEquals(['Connaught Place, New Delhi']);
        check(vm.recents.first.address).equals('Connaught Place, New Delhi');
      });
    });

    test('a denied permission surfaces as an error', () {
      fakeAsync((async) {
        final repo = FakeLocationRepository(
          currentError: const LocationPermissionException('Permission denied.'),
        );
        final vm = PickupSelectionViewModel(repository: repo);

        PickupLocation? pickup;
        var resolved = false;
        vm.useCurrentLocation().then((p) {
          pickup = p;
          resolved = true;
        });
        async.flushMicrotasks();

        check(vm.isLocating).isFalse();
        check(resolved).isTrue();
        check(pickup).isNull();
        check(vm.error).equals('Permission denied.');
      });
    });
  });
}
